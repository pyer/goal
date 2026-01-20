module time

#include <time.h>
#include <errno.h>

pub struct C.tm {
pub mut:
	tm_sec    int
	tm_min    int
	tm_hour   int
	tm_mday   int
	tm_mon    int
	tm_year   int
	tm_wday   int
	tm_yday   int
	tm_isdst  int
	tm_gmtoff int
}

// C.timeval represents a C time value.
pub struct C.timeval {
pub:
	tv_sec  u64
	tv_usec u64
}

type C.time_t = i64

fn C.time(t &C.time_t) C.time_t
fn C.localtime(t &C.time_t) &C.tm
// preferring localtime_r over the localtime because
// from docs localtime_r is thread safe,
fn C.localtime_r(t &C.time_t, tm &C.tm)
fn C.gmtime(t &C.time_t) &C.tm
fn C.gmtime_r(t &C.time_t, res &C.tm) &C.tm
fn C.strftime(buf &char, maxsize usize, const_format &char, const_tm &C.tm) usize

fn C.timegm(&C.tm) C.time_t


// now returns the current local time.
pub fn now() Time {
	// get the high precision time as UTC realtime clock
	// and use the nanoseconds part
	mut ts := C.timespec{}
	C.clock_gettime(C.CLOCK_REALTIME, &ts)
	loc_tm := C.tm{}
	C.localtime_r(voidptr(&ts.tv_sec), &loc_tm)
	return convert_ctime(loc_tm, int(ts.tv_nsec))
}

// utc returns the current UTC time.
pub fn utc() Time {
	// get the high precision time as UTC realtime clock
	// and use the nanoseconds part
	mut ts := C.timespec{}
	C.clock_gettime(C.CLOCK_REALTIME, &ts)
	return unix_nanosecond(i64(ts.tv_sec), int(ts.tv_nsec))
}

fn time_with_unix(t Time) Time {
	if t.unix != 0 {
		return t
	}
	tt := C.tm{
		tm_sec:  t.second
		tm_min:  t.minute
		tm_hour: t.hour
		tm_mday: t.day
		tm_mon:  t.month - 1
		tm_year: t.year - 1900
	}
	utime := make_unix_time(tt)
	return Time{
		...t
		unix: utime
	}
}

// ticks returns the number of milliseconds since the UNIX epoch.
// On Windows ticks returns the number of milliseconds elapsed since system start.
pub fn ticks() i64 {
		ts := C.timeval{}
		C.gettimeofday(&ts, 0)
		return i64(ts.tv_sec * u64(1000) + (ts.tv_usec / u64(1_000)))
}

// str returns the time in the same format as `parse` expects ("YYYY-MM-DD HH:mm:ss").
pub fn (t Time) str() string {
	// TODO: Define common default format for
	// `str` and `parse` and use it in both ways
	return t.format_ss()
}

// convert_ctime converts a C time to V time.
fn convert_ctime(t C.tm, nanosecond int) Time {
	return Time{
		year:       t.tm_year + 1900
		month:      t.tm_mon + 1
		day:        t.tm_mday
		hour:       t.tm_hour
		minute:     t.tm_min
		second:     t.tm_sec
		nanosecond: nanosecond
		unix:       make_unix_time(t)
		// for the actual code base when we
		// call convert_ctime, it is always
		// when we manage the local time.
		is_local: true
	}
}

// strftime returns the formatted time using `strftime(3)`.
pub fn (t Time) strftime(fmt string) string {
	mut tm := &C.tm{}
	C.gmtime_r(voidptr(&t.unix), tm)
	mut buf := [1024]char{}
	fmt_c := unsafe { &char(fmt.str) }
	C.strftime(&buf[0], usize(sizeof(buf)), fmt_c, tm)
	return unsafe { cstring_to_vstring(&char(&buf[0])) }
}

// some *nix system functions (e.g. `C.poll()`, C.epoll_wait()) accept an `int`
// value as *timeout in milliseconds* with the special value `-1` meaning "infinite"
pub fn (d Duration) sys_milliseconds() int {
	if d > 2147483647 * millisecond { // treat 2147483647000001 .. C.INT64_MAX as "infinite"
		return -1
	} else if d <= 0 {
		return 0 // treat negative timeouts as 0 - consistent with Unix behaviour
	} else {
		return int(d / millisecond)
	}
}


fn make_unix_time(t C.tm) i64 {
	return unsafe { i64(C.timegm(&t)) }
}

// local returns t with the location set to local time.
pub fn (t Time) local() Time {
	if t.is_local {
		return t
	}
	loc_tm := C.tm{}
	t_ := t.unix()
	C.localtime_r(voidptr(&t_), &loc_tm)
	return convert_ctime(loc_tm, t.nanosecond)
}

// in most systems, these are __quad_t, which is an i64
pub struct C.timespec {
pub mut:
	tv_sec  i64
	tv_nsec i64
}

// the first arg is defined in include/bits/types.h as `__S32_TYPE`, which is `int`
fn C.clock_gettime(int, &C.timespec) int

fn C.nanosleep(req &C.timespec, rem &C.timespec) int

// sys_mono_now returns a *monotonically increasing time*, NOT a time adjusted for daylight savings, location etc.
pub fn sys_mono_now() u64 {
	$if macos {
		return sys_mono_now_darwin()
	} $else {
		ts := C.timespec{}
		C.clock_gettime(C.CLOCK_MONOTONIC, &ts)
		return u64(ts.tv_sec) * 1_000_000_000 + u64(ts.tv_nsec)
	}
}

/*
// Note: vpc_now is used by `v -profile` .
// It should NOT call *any other v function*, just C functions and casts.
@[inline]
fn vpc_now() u64 {
	ts := C.timespec{}
	C.clock_gettime(C.CLOCK_MONOTONIC, &ts)
	return u64(ts.tv_sec) * 1_000_000_000 + u64(ts.tv_nsec)
}

// dummy to compile with all compilers
fn win_now() Time {
	return Time{}
}

// dummy to compile with all compilers
fn win_utc() Time {
	return Time{}
}
*/

// return absolute timespec for now()+d
pub fn (d Duration) timespec() C.timespec {
	mut ts := C.timespec{}
	C.clock_gettime(C.CLOCK_REALTIME, &ts)
	d_sec := d / second
	d_nsec := d % second
	ts.tv_sec += d_sec
	ts.tv_nsec += d_nsec
	if ts.tv_nsec > i64(second) {
		ts.tv_nsec -= i64(second)
		ts.tv_sec++
	}
	return ts
}

// sleep suspends the execution of the calling thread for a given duration (in nanoseconds).
pub fn sleep(duration Duration) {
	mut req := C.timespec{duration / second, duration % second}
	rem := C.timespec{}
	for C.nanosleep(&req, &rem) < 0 {
		if C.errno == C.EINTR {
			// Interrupted by a signal handler
			req = rem
		} else {
			break
		}
	}
}
