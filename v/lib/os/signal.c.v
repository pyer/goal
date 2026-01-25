@[has_globals]
module os

#flag -lpthread
#include <signal.h>

@[typedef]
struct C.sigset_t {}

fn C.sigaddset(set &C.sigset_t, signum int) int
fn C.sigemptyset(set &C.sigset_t)
fn C.sigprocmask(how int, set &C.sigset_t, oldset &C.sigset_t) int

fn C.pthread_self() usize
fn C.signal(signal int, handlercb SignalHandler) voidptr

// g_main_thread_id and is_main_thread can be used to determine if the current thread is the main thread.
// if need to get the tid of the main thread, can use the global variable g_main_thread_id
// instead of using thread_id() every time.
__global g_main_thread_id = u64(C.pthread_self())

// is_main_thread returns whether the current thread is the main thread.
pub fn is_main_thread() bool {
	return g_main_thread_id == u64(C.pthread_self())
}

// signal will assign `handler` callback to be called when `signum` signal is received.
pub fn signal_opt(signum Signal, handler SignalHandler) !SignalHandler {
	C.errno = 0
	prev_handler := C.signal(int(signum), handler)
	if prev_handler == C.SIG_ERR {
		// errno isn't correctly set on Windows, but EINVAL is this only possible value it can take anyway
		return error_with_code(posix_get_error_msg(C.EINVAL), C.EINVAL)
	}
	return SignalHandler(prev_handler)
}

// A convenient way to ignore certain system signals when there is no need to process certain system signals,
// Masking of system signals under posix systems requires a distinction between main and background threads.
// Since there is no good way to easily tell whether the current thread is the main or background thread,
// So a global variable is introduced to make the distinction.

// An empty system signal handler (callback function) used to mask the specified system signal.
fn ignore_signal_handler(_signal Signal) {
}

// signal_ignore to mask system signals, e.g.: signal_ignore(.pipe, .urg, ...).
pub fn signal_ignore(args ...Signal) {
	if is_main_thread() {
		// for main thread.
		for arg in args {
			signal_opt(arg, ignore_signal_handler) or {}
		}
	} else {
		// for background threads.
		//signal_ignore_internal(...args)
		mask1 := C.sigset_t{}
		C.sigemptyset(&mask1)
		for arg in args {
			C.sigaddset(&mask1, int(arg))
		}
		C.sigprocmask(C.SIG_BLOCK, &mask1, unsafe { nil })
	}
}

