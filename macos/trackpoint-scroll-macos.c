#define _DARWIN_C_SOURCE

#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hid/IOHIDManager.h>
#include <IOKit/hid/IOHIDUsageTables.h>
#include <mach/mach_time.h>

#include <ctype.h>
#include <errno.h>
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "trackpoint_scroll/engine.h"
#include "trackpoint_scroll/profiles.h"

#define DEFAULT_VENDOR_ID  0x5859
#define DEFAULT_PRODUCT_ID 0x0001
#define SYNTHETIC_MARKER    ((int64_t)0x545053434d41434fULL) /* TPSCMACO */
#define RELEASE_GUARD_US    50000ULL

struct app_config {
    uint32_t vendor_id;
    uint32_t product_id;
    bool suppress_middle_click;
    double scroll_scale;
    struct tpsc_engine_config engine;
    struct tpsc_profile profile;
};

struct app_state {
    struct app_config cfg;
    struct tpsc_engine *engine;
    IOHIDManagerRef hid;
    CFMachPortRef event_tap;
    CFRunLoopSourceRef event_tap_source;
    CFRunLoopTimerRef tick_timer;
    bool target_seen;
    bool middle_down;
    bool scrolled;
    uint64_t next_tick_us;
    uint64_t suppress_middle_until_us;
    mach_timebase_info_data_t timebase;
};

static uint64_t
mach_to_us(const struct app_state *state, uint64_t ticks)
{
    long double ns = (long double)ticks * state->timebase.numer / state->timebase.denom;
    return (uint64_t)(ns / 1000.0L);
}

static uint64_t
now_us(const struct app_state *state)
{
    return mach_to_us(state, mach_absolute_time());
}

static char *
trim(char *s)
{
    while (isspace((unsigned char)*s))
        s++;
    if (*s == '\0')
        return s;

    char *end = s + strlen(s) - 1;
    while (end > s && isspace((unsigned char)*end))
        *end-- = '\0';
    return s;
}

static bool
parse_bool(const char *s, bool *out)
{
    if (!strcmp(s, "true") || !strcmp(s, "yes") || !strcmp(s, "on") || !strcmp(s, "1")) {
        *out = true;
        return true;
    }
    if (!strcmp(s, "false") || !strcmp(s, "no") || !strcmp(s, "off") || !strcmp(s, "0")) {
        *out = false;
        return true;
    }
    return false;
}

static bool
parse_double(const char *s, double *out)
{
    char *end = NULL;
    errno = 0;
    double v = strtod(s, &end);
    if (errno || end == s || *trim(end) != '\0' || !isfinite(v))
        return false;
    *out = v;
    return true;
}

static bool
parse_long(const char *s, long *out)
{
    char *end = NULL;
    errno = 0;
    long v = strtol(s, &end, 0);
    if (errno || end == s || *trim(end) != '\0')
        return false;
    *out = v;
    return true;
}

static void
config_defaults(struct app_config *cfg)
{
    memset(cfg, 0, sizeof(*cfg));
    cfg->vendor_id = DEFAULT_VENDOR_ID;
    cfg->product_id = DEFAULT_PRODUCT_ID;
    cfg->suppress_middle_click = true;
    cfg->scroll_scale = 1.0;

    tpsc_engine_config_defaults(&cfg->engine);
    tpsc_profile_defaults_hyperbolic(&cfg->profile);
    cfg->engine.transform.apply = tpsc_profile_transform;
    cfg->engine.transform.reset = NULL;
    cfg->engine.transform.userdata = &cfg->profile;
}

static bool
set_profile(struct app_config *cfg, const char *value)
{
    if (!strcmp(value, "affine") || !strcmp(value, "linear") || !strcmp(value, "flat")) {
        cfg->profile.kind = TPSC_PROFILE_AFFINE;
        return true;
    }
    if (!strcmp(value, "quadratic")) {
        cfg->profile.kind = TPSC_PROFILE_QUADRATIC;
        return true;
    }
    if (!strcmp(value, "hyperbolic") || !strcmp(value, "asymptotic") ||
        !strcmp(value, "asymptotic-linear")) {
        cfg->profile.kind = TPSC_PROFILE_HYPERBOLIC;
        return true;
    }
    return false;
}

static bool
config_assignment(struct app_config *cfg, const char *key, char *value)
{
    double d;
    long l;
    bool b;

    if (!strcmp(key, "profile"))
        return set_profile(cfg, value);
    if (!strcmp(key, "clamp_negative_output")) {
        if (!parse_bool(value, &b)) return false;
        cfg->profile.clamp_negative_output = b;
        return true;
    }
    if (!strcmp(key, "suppress_middle_click")) {
        if (!parse_bool(value, &b)) return false;
        cfg->suppress_middle_click = b;
        return true;
    }
    if (!strcmp(key, "scroll_scale")) {
        if (!parse_double(value, &d) || d <= 0.0) return false;
        cfg->scroll_scale = d;
        return true;
    }
    if (!strcmp(key, "first_step_distance")) {
        if (!parse_double(value, &d) || d < 0.0) return false;
        cfg->engine.first_step_distance = d;
        return true;
    }
    if (!strcmp(key, "first_step_axis_merge_ms")) {
        if (!parse_double(value, &d) || d < 0.0) return false;
        cfg->engine.first_step_axis_merge_ms = d;
        return true;
    }
    if (!strcmp(key, "first_step_max_reports")) {
        if (!parse_long(value, &l) || l < INT32_MIN || l > INT32_MAX) return false;
        cfg->engine.first_step_max_reports = (int)l;
        return true;
    }
    if (!strcmp(key, "idle_reset_ms")) {
        if (!parse_double(value, &d) || d < 0.0) return false;
        cfg->engine.idle_reset_ms = d;
        return true;
    }
    if (!strcmp(key, "affine_k") || !strcmp(key, "linear_k") || !strcmp(key, "flat_k")) {
        if (!parse_double(value, &d)) return false;
        cfg->profile.params.affine.k = d;
        return true;
    }
    if (!strcmp(key, "affine_b") || !strcmp(key, "linear_b") || !strcmp(key, "flat_b")) {
        if (!parse_double(value, &d)) return false;
        cfg->profile.params.affine.b = d;
        return true;
    }
    if (!strcmp(key, "quadratic_a")) {
        if (!parse_double(value, &d)) return false;
        cfg->profile.params.quadratic.a = d;
        return true;
    }
    if (!strcmp(key, "quadratic_h")) {
        if (!parse_double(value, &d)) return false;
        cfg->profile.params.quadratic.h = d;
        return true;
    }
    if (!strcmp(key, "quadratic_k")) {
        if (!parse_double(value, &d)) return false;
        cfg->profile.params.quadratic.k = d;
        return true;
    }
    if (!strcmp(key, "hyperbolic_a") || !strcmp(key, "asymptotic_a")) {
        if (!parse_double(value, &d)) return false;
        cfg->profile.params.hyperbolic.a = d;
        return true;
    }
    if (!strcmp(key, "hyperbolic_u") || !strcmp(key, "asymptotic_u")) {
        if (!parse_double(value, &d)) return false;
        cfg->profile.params.hyperbolic.u = d;
        return true;
    }
    if (!strcmp(key, "hyperbolic_k") || !strcmp(key, "asymptotic_k")) {
        if (!parse_double(value, &d)) return false;
        cfg->profile.params.hyperbolic.k = d;
        return true;
    }

    fprintf(stderr, "warning: unknown config key '%s' ignored\n", key);
    return true;
}

static bool
load_config(struct app_config *cfg, const char *path)
{
    if (!path)
        return true;

    FILE *fp = fopen(path, "r");
    if (!fp) {
        fprintf(stderr, "cannot open config %s: %s\n", path, strerror(errno));
        return false;
    }

    char line[256];
    unsigned lineno = 0;
    while (fgets(line, sizeof(line), fp)) {
        lineno++;
        char *comment = strchr(line, '#');
        if (comment) *comment = '\0';
        char *p = trim(line);
        if (*p == '\0' || *p == ';' || *p == '[')
            continue;
        char *eq = strchr(p, '=');
        if (!eq) {
            fprintf(stderr, "%s:%u: malformed line\n", path, lineno);
            fclose(fp);
            return false;
        }
        *eq = '\0';
        char *key = trim(p);
        char *value = trim(eq + 1);
        if (!config_assignment(cfg, key, value)) {
            fprintf(stderr, "%s:%u: invalid value for %s\n", path, lineno, key);
            fclose(fp);
            return false;
        }
    }

    if (ferror(fp)) {
        fprintf(stderr, "error reading %s\n", path);
        fclose(fp);
        return false;
    }
    fclose(fp);
    return true;
}

static void
mark_synthetic(CGEventRef event)
{
    CGEventSetIntegerValueField(event, kCGEventSourceUserData, SYNTHETIC_MARKER);
}

static void
post_middle_pair(void)
{
    CGEventRef probe = CGEventCreate(NULL);
    if (!probe)
        return;
    CGPoint location = CGEventGetLocation(probe);
    CFRelease(probe);

    CGEventRef down = CGEventCreateMouseEvent(NULL, kCGEventOtherMouseDown,
                                              location, kCGMouseButtonCenter);
    CGEventRef up = CGEventCreateMouseEvent(NULL, kCGEventOtherMouseUp,
                                            location, kCGMouseButtonCenter);
    if (down) {
        mark_synthetic(down);
        CGEventSetIntegerValueField(down, kCGMouseEventButtonNumber, 2);
        CGEventPost(kCGHIDEventTap, down);
        CFRelease(down);
    }
    if (up) {
        mark_synthetic(up);
        CGEventSetIntegerValueField(up, kCGMouseEventButtonNumber, 2);
        CGEventPost(kCGHIDEventTap, up);
        CFRelease(up);
    }
}

static void
post_scroll(const struct app_state *state, struct tpsc_vec v)
{
    double vertical = -v.y * state->cfg.scroll_scale;
    double horizontal = v.x * state->cfg.scroll_scale;
    if (vertical == 0.0 && horizontal == 0.0)
        return;

    int32_t vi = (int32_t)llround(vertical);
    int32_t hi = (int32_t)llround(horizontal);
    CGEventRef event = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitPixel,
                                                     2, vi, hi);
    if (!event)
        return;

    mark_synthetic(event);
    CGEventSetIntegerValueField(event, kCGScrollWheelEventIsContinuous, 1);
    CGEventSetDoubleValueField(event, kCGScrollWheelEventPointDeltaAxis1, vertical);
    CGEventSetDoubleValueField(event, kCGScrollWheelEventPointDeltaAxis2, horizontal);
    CGEventSetIntegerValueField(event, kCGScrollWheelEventFixedPtDeltaAxis1,
                                (int64_t)llround(vertical * 65536.0));
    CGEventSetIntegerValueField(event, kCGScrollWheelEventFixedPtDeltaAxis2,
                                (int64_t)llround(horizontal * 65536.0));
    CGEventPost(kCGHIDEventTap, event);
    CFRelease(event);
}

static void
tick_callback(CFRunLoopTimerRef timer, void *context)
{
    (void)timer;
    struct app_state *state = context;
    if (!state->middle_down || !tpsc_engine_needs_ticks(state->engine))
        return;

    uint64_t now = now_us(state);
    uint32_t step = tpsc_engine_tick_us(state->engine);
    if (state->next_tick_us == 0)
        state->next_tick_us = now;

    unsigned catchup = 0;
    while (state->next_tick_us <= now && tpsc_engine_needs_ticks(state->engine) && catchup++ < 64) {
        struct tpsc_vec output = {0.0, 0.0};
        int rc = tpsc_engine_tick(state->engine, state->next_tick_us, &output);
        if (rc != TPSC_OK) {
            fprintf(stderr, "engine tick failed: %d\n", rc);
            state->next_tick_us = 0;
            return;
        }
        if (output.x != 0.0 || output.y != 0.0) {
            state->scrolled = true;
            post_scroll(state, output);
        }
        state->next_tick_us += step;
    }

    if (!tpsc_engine_needs_ticks(state->engine))
        state->next_tick_us = 0;
}

static void
handle_middle(struct app_state *state, bool down, uint64_t time_us)
{
    if (down == state->middle_down)
        return;

    if (down) {
        int rc = tpsc_engine_begin(state->engine, time_us);
        if (rc != TPSC_OK)
            fprintf(stderr, "engine begin failed: %d\n", rc);
        state->middle_down = true;
        state->scrolled = false;
        state->next_tick_us = 0;
        state->suppress_middle_until_us = time_us + RELEASE_GUARD_US;
    } else {
        int rc = tpsc_engine_end(state->engine, time_us);
        if (rc != TPSC_OK)
            fprintf(stderr, "engine end failed: %d\n", rc);
        bool replay_click = !state->scrolled && !state->cfg.suppress_middle_click;
        state->middle_down = false;
        state->next_tick_us = 0;
        state->suppress_middle_until_us = time_us + RELEASE_GUARD_US;
        if (replay_click)
            post_middle_pair();
    }
}

static void
hid_value_callback(void *context, IOReturn result, void *sender, IOHIDValueRef value)
{
    (void)sender;
    if (result != kIOReturnSuccess)
        return;

    struct app_state *state = context;
    IOHIDElementRef element = IOHIDValueGetElement(value);
    uint32_t page = IOHIDElementGetUsagePage(element);
    uint32_t usage = IOHIDElementGetUsage(element);
    CFIndex ivalue = IOHIDValueGetIntegerValue(value);
    uint64_t time_us = mach_to_us(state, IOHIDValueGetTimeStamp(value));

    if (page == kHIDPage_Button && usage == 3) {
        handle_middle(state, ivalue != 0, time_us);
        return;
    }

    if (!state->middle_down || page != kHIDPage_GenericDesktop ||
        !IOHIDElementIsRelative(element))
        return;

    struct tpsc_vec delta = {0.0, 0.0};
    if (usage == kHIDUsage_GD_X)
        delta.x = (double)ivalue;
    else if (usage == kHIDUsage_GD_Y)
        delta.y = (double)ivalue;
    else
        return;

    if (delta.x == 0.0 && delta.y == 0.0)
        return;

    int rc = tpsc_engine_feed(state->engine, time_us, delta);
    if (rc != TPSC_OK) {
        fprintf(stderr, "engine feed failed: %d\n", rc);
        return;
    }
    if (state->next_tick_us == 0)
        state->next_tick_us = time_us + tpsc_engine_tick_us(state->engine);
}

static void
device_matched(void *context, IOReturn result, void *sender, IOHIDDeviceRef device)
{
    (void)sender;
    struct app_state *state = context;
    if (result != kIOReturnSuccess)
        return;
    state->target_seen = true;

    CFTypeRef product = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductKey));
    char name[256] = "(unknown)";
    if (product && CFGetTypeID(product) == CFStringGetTypeID())
        CFStringGetCString((CFStringRef)product, name, sizeof(name), kCFStringEncodingUTF8);
    fprintf(stderr, "matched HID device: %s (vid=%04x pid=%04x)\n",
            name, state->cfg.vendor_id, state->cfg.product_id);
}

static void
device_removed(void *context, IOReturn result, void *sender, IOHIDDeviceRef device)
{
    (void)result;
    (void)sender;
    (void)device;
    struct app_state *state = context;
    state->target_seen = false;
    if (state->middle_down)
        handle_middle(state, false, now_us(state));
    fprintf(stderr, "target HID device removed\n");
}

static CGEventRef
event_tap_callback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *context)
{
    (void)proxy;
    struct app_state *state = context;

    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        CGEventTapEnable(state->event_tap, true);
        return event;
    }

    if (CGEventGetIntegerValueField(event, kCGEventSourceUserData) == SYNTHETIC_MARKER)
        return event;

    uint64_t now = now_us(state);
    bool middle_guard = state->middle_down || now <= state->suppress_middle_until_us;

    if ((type == kCGEventOtherMouseDown || type == kCGEventOtherMouseUp) && middle_guard) {
        int64_t button = CGEventGetIntegerValueField(event, kCGMouseEventButtonNumber);
        if (button == 2)
            return NULL;
    }

    if (state->middle_down &&
        (type == kCGEventMouseMoved || type == kCGEventOtherMouseDragged ||
         type == kCGEventLeftMouseDragged || type == kCGEventRightMouseDragged))
        return NULL;

    return event;
}

static CFMutableDictionaryRef
make_match(uint32_t vendor, uint32_t product)
{
    CFMutableDictionaryRef dict = CFDictionaryCreateMutable(NULL, 0,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (!dict)
        return NULL;

    int v = (int)vendor;
    int p = (int)product;
    CFNumberRef vn = CFNumberCreate(NULL, kCFNumberIntType, &v);
    CFNumberRef pn = CFNumberCreate(NULL, kCFNumberIntType, &p);
    if (!vn || !pn) {
        if (vn) CFRelease(vn);
        if (pn) CFRelease(pn);
        CFRelease(dict);
        return NULL;
    }
    CFDictionarySetValue(dict, CFSTR(kIOHIDVendorIDKey), vn);
    CFDictionarySetValue(dict, CFSTR(kIOHIDProductIDKey), pn);
    CFRelease(vn);
    CFRelease(pn);
    return dict;
}

static bool
setup_hid(struct app_state *state)
{
    state->hid = IOHIDManagerCreate(NULL, kIOHIDOptionsTypeNone);
    if (!state->hid)
        return false;

    CFMutableDictionaryRef match = make_match(state->cfg.vendor_id, state->cfg.product_id);
    if (!match)
        return false;
    IOHIDManagerSetDeviceMatching(state->hid, match);
    CFRelease(match);

    IOHIDManagerRegisterDeviceMatchingCallback(state->hid, device_matched, state);
    IOHIDManagerRegisterDeviceRemovalCallback(state->hid, device_removed, state);
    IOHIDManagerRegisterInputValueCallback(state->hid, hid_value_callback, state);
    IOHIDManagerScheduleWithRunLoop(state->hid, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);

    IOReturn rc = IOHIDManagerOpen(state->hid, kIOHIDOptionsTypeNone);
    if (rc != kIOReturnSuccess) {
        fprintf(stderr, "IOHIDManagerOpen failed: 0x%x\n", rc);
        return false;
    }
    return true;
}

static bool
setup_event_tap(struct app_state *state)
{
    CGEventMask mask = CGEventMaskBit(kCGEventMouseMoved) |
                       CGEventMaskBit(kCGEventLeftMouseDragged) |
                       CGEventMaskBit(kCGEventRightMouseDragged) |
                       CGEventMaskBit(kCGEventOtherMouseDragged) |
                       CGEventMaskBit(kCGEventOtherMouseDown) |
                       CGEventMaskBit(kCGEventOtherMouseUp);

    state->event_tap = CGEventTapCreate(kCGHIDEventTap, kCGHeadInsertEventTap,
                                        kCGEventTapOptionDefault, mask,
                                        event_tap_callback, state);
    if (!state->event_tap) {
        fprintf(stderr, "cannot create HID event tap; grant Input Monitoring/Accessibility access\n");
        return false;
    }

    state->event_tap_source = CFMachPortCreateRunLoopSource(NULL, state->event_tap, 0);
    if (!state->event_tap_source)
        return false;
    CFRunLoopAddSource(CFRunLoopGetCurrent(), state->event_tap_source, kCFRunLoopCommonModes);
    CGEventTapEnable(state->event_tap, true);
    return true;
}

static bool
setup_timer(struct app_state *state)
{
    CFRunLoopTimerContext ctx = {0, state, NULL, NULL, NULL};
    state->tick_timer = CFRunLoopTimerCreate(NULL,
        CFAbsoluteTimeGetCurrent() + 0.001, 0.001, 0, 0, tick_callback, &ctx);
    if (!state->tick_timer)
        return false;
    CFRunLoopAddTimer(CFRunLoopGetCurrent(), state->tick_timer, kCFRunLoopCommonModes);
    return true;
}

static void
usage(const char *argv0)
{
    fprintf(stderr,
        "usage: %s [--config PATH] [--vendor ID] [--product ID]\n"
        "defaults: vendor=0x%04x product=0x%04x\n",
        argv0, DEFAULT_VENDOR_ID, DEFAULT_PRODUCT_ID);
}

int
main(int argc, char **argv)
{
    struct app_state state;
    memset(&state, 0, sizeof(state));
    config_defaults(&state.cfg);
    mach_timebase_info(&state.timebase);

    const char *config_path = NULL;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--config") && i + 1 < argc) {
            config_path = argv[++i];
        } else if ((!strcmp(argv[i], "--vendor") || !strcmp(argv[i], "--product")) && i + 1 < argc) {
            bool vendor = !strcmp(argv[i], "--vendor");
            char *end = NULL;
            unsigned long n = strtoul(argv[++i], &end, 0);
            if (!end || *end != '\0' || n > UINT32_MAX) {
                usage(argv[0]);
                return 2;
            }
            if (vendor) state.cfg.vendor_id = (uint32_t)n;
            else state.cfg.product_id = (uint32_t)n;
        } else if (!strcmp(argv[i], "--help")) {
            usage(argv[0]);
            return 0;
        } else {
            usage(argv[0]);
            return 2;
        }
    }

    if (!load_config(&state.cfg, config_path))
        return 2;

    state.cfg.engine.transform.apply = tpsc_profile_transform;
    state.cfg.engine.transform.reset = NULL;
    state.cfg.engine.transform.userdata = &state.cfg.profile;
    int validation = tpsc_engine_config_validate(&state.cfg.engine);
    if (validation != TPSC_OK) {
        fprintf(stderr, "invalid engine configuration: %d\n", validation);
        return 2;
    }

    int status = TPSC_OK;
    state.engine = tpsc_engine_create(&state.cfg.engine, &status);
    if (!state.engine) {
        fprintf(stderr, "cannot create scroll engine: %d\n", status);
        return 1;
    }

    if (!CGPreflightListenEventAccess())
        (void)CGRequestListenEventAccess();
    if (!CGPreflightPostEventAccess())
        (void)CGRequestPostEventAccess();
    if (!CGPreflightListenEventAccess() || !CGPreflightPostEventAccess()) {
        fprintf(stderr,
            "macOS permission is missing. Grant this executable/terminal Input Monitoring and Accessibility access, then rerun.\n");
        tpsc_engine_destroy(state.engine);
        return 1;
    }

    if (!setup_event_tap(&state) || !setup_hid(&state) || !setup_timer(&state)) {
        fprintf(stderr, "initialization failed\n");
        tpsc_engine_destroy(state.engine);
        return 1;
    }

    fprintf(stderr,
        "trackpoint-scroll-macos running for vid=%04x pid=%04x; middle+TrackPoint motion scrolls\n",
        state.cfg.vendor_id, state.cfg.product_id);
    CFRunLoopRun();

    if (state.tick_timer) CFRelease(state.tick_timer);
    if (state.event_tap_source) CFRelease(state.event_tap_source);
    if (state.event_tap) CFRelease(state.event_tap);
    if (state.hid) {
        IOHIDManagerClose(state.hid, kIOHIDOptionsTypeNone);
        CFRelease(state.hid);
    }
    tpsc_engine_destroy(state.engine);
    return 0;
}
