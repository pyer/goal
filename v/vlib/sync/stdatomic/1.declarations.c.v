module stdatomic

#flag -I vlib/sync/stdatomic
#insert "vlib/sync/stdatomic/atomic.h"

// The following functions are actually generic in C
fn C.atomic_load_ptr(voidptr) voidptr
fn C.atomic_store_ptr(voidptr, voidptr)
fn C.atomic_compare_exchange_weak_ptr(voidptr, voidptr, isize) bool
fn C.atomic_compare_exchange_strong_ptr(voidptr, voidptr, isize) bool
fn C.atomic_exchange_ptr(voidptr, voidptr) voidptr
fn C.atomic_fetch_add_ptr(voidptr, voidptr) voidptr
fn C.atomic_fetch_sub_ptr(voidptr, voidptr) voidptr

fn C.atomic_load_byte(voidptr) u8
fn C.atomic_store_byte(voidptr, u8)
fn C.atomic_compare_exchange_weak_byte(voidptr, voidptr, u8) bool
fn C.atomic_compare_exchange_strong_byte(voidptr, voidptr, u8) bool
fn C.atomic_exchange_byte(voidptr, u8) u8
fn C.atomic_fetch_add_byte(voidptr, u8) u8
fn C.atomic_fetch_sub_byte(voidptr, u8) u8

fn C.atomic_load_u16(voidptr) u16
fn C.atomic_store_u16(voidptr, u16)
fn C.atomic_compare_exchange_weak_u16(voidptr, voidptr, u16) bool
fn C.atomic_compare_exchange_strong_u16(voidptr, voidptr, u16) bool
fn C.atomic_exchange_u16(voidptr, u16) u16
fn C.atomic_fetch_add_u16(voidptr, u16) u16
fn C.atomic_fetch_sub_u16(voidptr, u16) u16

fn C.atomic_load_u32(voidptr) u32
fn C.atomic_store_u32(voidptr, u32)
fn C.atomic_compare_exchange_weak_u32(voidptr, voidptr, u32) bool
fn C.atomic_compare_exchange_strong_u32(voidptr, voidptr, u32) bool
fn C.atomic_exchange_u32(voidptr, u32) u32
fn C.atomic_fetch_add_u32(voidptr, u32) u32
fn C.atomic_fetch_sub_u32(voidptr, u32) u32

fn C.atomic_load_u64(voidptr) u64
fn C.atomic_store_u64(voidptr, u64)
fn C.atomic_compare_exchange_weak_u64(voidptr, voidptr, u64) bool
fn C.atomic_compare_exchange_strong_u64(voidptr, voidptr, u64) bool
fn C.atomic_exchange_u64(voidptr, u64) u64
fn C.atomic_fetch_add_u64(voidptr, u64) u64
fn C.atomic_fetch_sub_u64(voidptr, u64) u64

fn C.atomic_thread_fence(int)
fn C.cpu_relax()

fn C.ANNOTATE_RWLOCK_CREATE(voidptr)
fn C.ANNOTATE_RWLOCK_ACQUIRED(voidptr, int)
fn C.ANNOTATE_RWLOCK_RELEASED(voidptr, int)
fn C.ANNOTATE_RWLOCK_DESTROY(voidptr)

$if valgrind ? {
	#flag -I/usr/include/valgrind
	#include <valgrind/helgrind.h>
}
