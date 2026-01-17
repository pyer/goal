// Copyright (c) 2019-2024 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module pref

// import v.ast // TODO: this results in a compiler bug
import os.cmdline
import os

pub enum BuildMode {
	// `v program.v'
	// Build user code only, and add pre-compiled vlib (`cc program.o builtin.o os.o...`)
	default_mode // `v -lib ~/v/os`
	// build any module (generate os.o + os.vh)
	build_module
}

pub enum AssertFailureMode {
	default
	aborts
	backtraces
	continues
}

pub enum GarbageCollectionMode {
	unknown
	no_gc
	boehm_full     // full garbage collection mode
	boehm_incr     // incremental garbage collection mode
	boehm_full_opt // full garbage collection mode
	boehm_incr_opt // incremental garbage collection mode
	boehm_leak     // leak detection mode (makes `gc_check_leaks()` work)
}

pub enum OutputMode {
	stdout
	silent
}

pub enum ColorOutput {
	auto
	always
	never
}

pub enum CompilerType {
	gcc
	tinyc
	clang
	emcc
	mingw
	cplusplus
}

pub const supported_test_runners = ['normal', 'simple', 'tap', 'dump', 'teamcity']

@[heap; minify]
pub struct Preferences {
pub mut:
	arch                Arch
	os                  OS // the OS to compile for
	build_mode          BuildMode
	output_mode         OutputMode = .stdout
	// verbosity           VerboseLevel
	is_verbose bool
	is_test            bool   // `v test string_test.v`
	is_prod            bool   // use "-O3"
	no_prod_options    bool   // `-no-prod-options`, means do not pass any optimization flags to the C compilation, while still allowing the user to use for example `-cflags -Os` to pass custom ones
	is_repl            bool
	is_debug           bool // turned on by -g/-debug or -cg/-cdebug, it tells v to pass -g to the C backend compiler.
	show_asserts       bool // `VTEST_SHOW_ASSERTS=1 v file_test.v` will show details about the asserts done by a test file. Also activated for `-stats` and `-show-asserts`.
	show_timings       bool // show how much time each compiler stage took
	show_version       bool // -v, -V, -version or --version was passed
	show_help          bool // -?, -h, -help or --help was passed
	is_fmt             bool
	is_vet             bool
	is_vweb            bool // skip _ var warning in templates
	is_apk             bool     // build as Android .apk format
	is_cstrict         bool     // turn on more C warnings; slightly slower
	is_callstack       bool     // turn on callstack registers on each call when v.debug is imported
	is_trace           bool     // turn on possibility to trace fn call where v.debug is imported
	is_check_return    bool     // -check-return, will make V produce notices about *all* call expressions with unused results. NOTE: experimental!
	is_check_overflow  bool     // -check-overflow, will panic on integer overflow
  keepc              bool     // keep the C source file
	test_runner        string   // can be 'simple' (fastest, but much less detailed), 'tap', 'normal'
	translated         bool     // `v translate doom.v` are we running V code translated from C? allow globals, ++ expressions, etc
	hide_auto_str      bool // `v -hide-auto-str program.v`, doesn't generate str() with struct data
	sanitize               bool // use Clang's new "-fsanitize" option
	show_cc                bool   // -showcc, print cc command
	show_c_output          bool   // -show-c-output, print all cc output even if the code was compiled correctly
	show_callgraph         bool   // -show-callgraph, print the program callgraph, in a Graphviz DOT format to stdout
	show_depgraph          bool   // -show-depgraph, print the program module dependency graph, in a Graphviz DOT format to stdout
	show_unused_params     bool   // NOTE: temporary until making it a default.
	use_os_system_to_run   bool // when set, use os.system() to run the produced executable, instead of os.new_process; works around segfaults on macos, that may happen when xcode is updated
	// TODO: Convert this into a []string
	cflags  string // Additional options which will be passed to the C compiler *before* other options.
	ldflags string // Additional options which will be passed to the C compiler *after* everything else.
	// For example, passing -cflags -Os will cause the C compiler to optimize the generated binaries for size.
	// You could pass several -cflags XXX arguments. They will be merged with each other.
	// You can also quote several options at the same time: -cflags '-Os -fno-inline-small-functions'.
	m64                       bool         // true = generate 64-bit code, defaults to x64
	no_bounds_checking        bool   // `-no-bounds-checking` turns off *all* bounds checks for all functions at runtime, as if they all had been tagged with `@[direct_array_access]`
	force_bounds_checking     bool   // `-force-bounds-checking` turns ON *all* bounds checks, even for functions that *were* tagged with `@[direct_array_access]`
	autofree                  bool   // `v -manualfree` => false, `v -autofree` => true; false by default for now.
	print_autofree_vars       bool   // print vars that are not freed by autofree
	print_autofree_vars_in_fn string // same as above, but only for a single fn
	// Disabling `free()` insertion results in better performance in some applications (e.g. compilers)
	trace_calls bool     // -trace-calls true = the transformer stage will generate and inject print calls for tracing function calls
	trace_fns   []string // when set, tracing will be done only for functions, whose names match the listed patterns.
	// generating_vh    bool
	no_builtin       bool   // Skip adding the `builtin` module implicitly. The generated C code may not compile.
	enable_globals   bool   // allow __global for low level code
	is_bare          bool   // set by -freestanding
	bare_builtin_dir string // Set by -bare-builtin-dir xyz/ . The xyz/ module should contain implementations of malloc, memset, etc, that are used by the rest of V's `builtin` module. That option is only useful with -freestanding (i.e. when is_bare is true).
	no_closures      bool   // Produce a compile time error, if a closure was generated for any reason (an implicit receiver method was stored, or an explicit `fn [captured]()`).
	lookup_path      []string
	prealloc         bool
	vexe             string
	vroot            string
	vlib             string   // absolute path to the lib folder
  vmodules         string   // absolute path to the modules folder
	vmodules_paths   []string // absolute paths to the vmodules folders, by default ['/home/user/.vmodules'], can be overridden by setting VMODULES
	path             string // Path to the source file to compile
	line_info        string // `-line-info="file.v:28"`: for "mini VLS" (shows information about objects on provided line)
	linfo            LineInfo

	exclude   []string // glob patterns for excluding .v files from the list of .v files that otherwise would have been used for a compilation, example: `-exclude @vlib/math/*.c.v`
	file_list []string // A list of .v files or directories. All .v files found recursively in directories will be included in the compilation.
	// Only test_ functions that match these patterns will be run. -run-only is valid only for _test.v files.
	// -d vfmt and -d another=0 for `$if vfmt { will execute }` and `$if another ? { will NOT get here }`
	compile_defines     []string          // just ['vfmt']
	compile_defines_all []string          // contains both: ['vfmt','another']
	compile_values      map[string]string // the map will contain for `-d key=value`: compile_values['key'] = 'value', and for `-d ident`, it will be: compile_values['ident'] = 'true'

	run_args     []string // `v run x.v 1 2 3` => `1 2 3`

	skip_warnings    bool // like C's "-w", forces warnings to be ignored.
	skip_notes       bool // force notices to be ignored/not shown.
	warn_impure_v    bool // -Wimpure-v, force a warning for JS.fn()/C.fn(), outside of .js.v/.c.v files. TODO: turn to an error by default
	warns_are_errors bool // -W, like C's "-Werror", treat *every* warning is an error
	notes_are_errors bool // -N, treat *every* notice as an error
	fatal_errors     bool // unconditionally exit after the first error with exit(1)

	only_check_syntax bool // when true, just parse the files, then stop, before running checker
	check_only        bool // same as only_check_syntax, but also runs the checker
	experimental      bool // enable experimental features
	skip_unused       bool // skip generating C code for functions, that are not used

	use_color           ColorOutput // whether the warnings/errors should use ANSI color escapes.
	cleanup_files       []string    // list of temporary *.tmp.c and *.tmp.c.rsp files. Cleaned up on successful builds.
	assert_failure_mode AssertFailureMode // whether to call abort() or print_backtrace() after an assertion failure
	message_limit       int = 200 // the maximum amount of warnings/errors/notices that will be accumulated
	nofloat             bool // for low level code, like kernels: replaces f32 with u32 and f64 with u64
	use_coroutines      bool // experimental coroutines
	fast_math           bool // -fast-math will pass -ffast-math to the C backend
	// checker settings:
	checker_match_exhaustive_cutoff_limit int = 12
	thread_stack_size                     int = 8388608 // Change with `-thread-stack-size 4194304`. Note: on macos it was 524288, which is too small for more complex programs with many nested callexprs.
	// wasm settings:
	wasm_stack_top    int = 1024 + (16 * 1024) // stack size for webassembly backend
	wasm_validate     bool // validate webassembly code, by calling `wasm-validate`
	warn_about_allocs bool // -warn-about-allocs warngs about every single allocation, e.g. 'hi $name'. Mostly for low level development where manual memory management is used.
	// game prototyping flags:
	div_by_zero_is_zero bool // -div-by-zero-is-zero makes so `x / 0 == 0`, i.e. eliminates the division by zero panics/segfaults
	// forwards compatibility settings:
	relaxed_gcc14 bool = true // turn on the generated pragmas, that make gcc versions > 14 a lot less pedantic. The default is to have those pragmas in the generated C output, so that gcc-14 can be used on Arch etc.
	//
	is_vls        bool
	json_errors   bool // -json-errors, for VLS and other tools
	new_transform bool // temporary for the new transformer
}

//pub fn parse_args_and_show_errors(args []string) (&Preferences) {
pub fn parse_args_and_show_errors() (&Preferences) {
	mut res := &Preferences{}
  args := os.args
	$if x64 {
		res.m64 = true // follow V model by default
	}

	mut no_skip_unused := false
	for i := 0; i < args.len; i++ {
		arg := args[i]
		match arg {
			'--' {
				break
			}
			'-wasm-validate' {
				res.wasm_validate = true
			}
			'-wasm-stack-top' {
				res.wasm_stack_top = cmdline.option(args[i..], arg, res.wasm_stack_top.str()).int()
				i++
			}
			'-assert' {
				assert_mode := cmdline.option(args[i..], '-assert', '')
				match assert_mode {
					'aborts' {
						res.assert_failure_mode = .aborts
					}
					'backtraces' {
						res.assert_failure_mode = .backtraces
					}
					'continues' {
						res.assert_failure_mode = .continues
					}
					else {
						eprintln('unknown assert mode `-gc ${assert_mode}`, supported modes are:`')
						eprintln('  `-assert aborts`     .... calls abort() after assertion failure')
						eprintln('  `-assert backtraces` .... calls print_backtrace() after assertion failure')
						eprintln('  `-assert continues`  .... does not call anything, just continue after an assertion failure')
						exit(1)
					}
				}
				i++
			}
			'-show-timings' {
				res.show_timings = true
			}
			'-show-asserts' {
				res.show_asserts = true
			}
			'-check-syntax' {
				res.only_check_syntax = true
			}
			'-check' {
				res.check_only = true
			}
			'-vls-mode' {
				res.is_vls = true
			}
			'-verbose' {
				res.is_verbose = true
			}
			'-?', '-h', '-help', '--help' {
				// Note: help is *very important*, just respond to all variations:
				res.show_help = true
			}
			'-v', '-V', '-version', '--version' {
        res.show_version = true
			}
			'-progress' {
				// processed by testing tools in cmd/tools/modules/testing/common.v
			}
			'-Wimpure-v' {
				res.warn_impure_v = true
			}
			'-Wfatal-errors' {
				res.fatal_errors = true
			}
			'-silent' {
				res.output_mode = .silent
			}
			'-cstrict' {
				res.is_cstrict = true
			}
			'-nofloat' {
				res.nofloat = true
				res.compile_defines_all << 'nofloat' // so that `$if nofloat? {` works
				res.compile_defines << 'nofloat'
			}
			'-fast-math' {
				res.fast_math = true
			}
			'-g', '-debug' {
				res.is_debug = true
			}
			'-warn-about-allocs' {
				res.warn_about_allocs = true
			}
			'-div-by-zero-is-zero' {
				res.div_by_zero_is_zero = true
			}
			'-repl' {
				res.is_repl = true
			}
			'-json-errors' {
				res.json_errors = true
			}
			'-enable-globals' {
				res.enable_globals = true
			}
			'-skip-unused' {
				res.skip_unused = true
			}
			'-no-skip-unused' {
				no_skip_unused = true
				res.skip_unused = false
			}
			'-force-bounds-checking' {
				res.force_bounds_checking = true
			}
			'-no-relaxed-gcc14' {
				res.relaxed_gcc14 = false
			}
			'-prod' {
				res.is_prod = true
			}
			'-hide-auto-str' {
				res.hide_auto_str = true
			}
			'-translated' {
				res.translated = true
			}
			'-m32', '-m64' {
				res.m64 = arg[2] == `6`
				res.cflags += ' ${arg}'
			}
			'-color' {
				res.use_color = .always
			}
			'-nocolor' {
				res.use_color = .never
			}
			'-keepc' {
				res.keepc = true
			}
			'-showcc' {
				res.show_cc = true
			}
			'-show-c-output' {
				res.show_c_output = true
			}
			'-show-callgraph' {
				res.show_callgraph = true
			}
			'-show-depgraph' {
				res.show_depgraph = true
			}
			'-exclude' {
				patterns := cmdline.option(args[i..], arg, '').split_any(',')
				res.exclude << patterns
				i++
			}
			'-file-list' {
				res.file_list = cmdline.option(args[i..], arg, '').split_any(',')
				i++
			}
			'-test-runner' {
				res.test_runner = cmdline.option(args[i..], arg, res.test_runner)
				i++
			}
			'-experimental' {
				res.experimental = true
			}
			'-new-transformer' {
				res.new_transform = true
			}
			'-use-os-system-to-run' {
				res.use_os_system_to_run = true
			}
			'-prealloc' {
				res.prealloc = true
			}
			'-W' {
				res.warns_are_errors = true
			}
			'-w' {
				res.skip_warnings = true
				res.warns_are_errors = false
			}
			'-N' {
				res.notes_are_errors = true
			}
			'-n' {
				res.skip_notes = true
				res.notes_are_errors = false
			}
			'-no-closures' {
				res.no_closures = true
			}
			'-d', '-define' {
				if define := args[i..][1] {
					res.parse_define(define)
				}
				i++
			}
			'-message-limit' {
				res.message_limit = cmdline.option(args[i..], arg, '5').int()
				i++
			}
			'-thread-stack-size' {
				res.thread_stack_size = cmdline.option(args[i..], arg, res.thread_stack_size.str()).int()
				i++
			}
			'-checker-match-exhaustive-cutoff-limit' {
				res.checker_match_exhaustive_cutoff_limit = cmdline.option(args[i..],
					arg, '10').int()
				i++
			}
			'-line-info' {
				res.line_info = cmdline.option(args[i..], arg, '')
				res.parse_line_info(res.line_info)
				i++
			}
			'-check-unused-fn-args' {
				res.show_unused_params = true
			}
			'-check-return' {
				res.is_check_return = true
			}
			'-check-overflow' {
				res.is_check_overflow = true
			}
			else {
        res.path = arg
			}
		}
	}
	if res.force_bounds_checking {
		res.no_bounds_checking = false
		res.compile_defines = res.compile_defines.filter(it == 'no_bounds_checking')
		res.compile_defines_all = res.compile_defines_all.filter(it == 'no_bounds_checking')
	}
	if res.trace_calls {
		if res.trace_fns.len == 0 {
			res.trace_fns << '*'
		}
		for mut fpattern in res.trace_fns {
			if fpattern.contains('*') {
				continue
			}
			fpattern = '*${fpattern}*'
		}
	}

	if res.fast_math {
		res.cflags += ' -ffast-math'
	}

	if res.is_bare {
		// make `$if freestanding? {` + file_freestanding.v + file_notd_freestanding.v work:
		res.compile_defines << 'freestanding'
		res.compile_defines_all << 'freestanding'
	}
	if 'callstack' in res.compile_defines_all {
		res.is_callstack = true
	}
	if 'trace' in res.compile_defines_all {
		res.is_trace = true
	}
	res.fill_with_defaults()
		res.skip_unused = res.build_mode != .build_module
		if no_skip_unused {
			res.skip_unused = false
		}

	return res
}

@[noreturn]
pub fn eprintln_exit(s string) {
	eprintln(s)
	exit(1)
}

pub fn eprintln_cond(condition bool, s string) {
	if !condition {
		return
	}
	eprintln(s)
}

pub fn (pref &Preferences) vrun_elog(s string) {
	if pref.is_verbose {
		eprintln('> v run -, ${s}')
	}
}

fn must_exist(path string) {
	if !os.exists(path) {
		eprintln_exit('v expects that `${path}` exists, but it does not')
	}
}

@[inline]
fn is_source_file(path string) bool {
	return path.ends_with('.v') || os.exists(path)
}

fn (mut prefs Preferences) parse_compile_value(define string) {
	if !define.contains('=') {
		eprintln_exit('V error: Define argument value missing for ${define}.')
		return
	}
	name := define.all_before('=')
	value := define.all_after_first('=')
	prefs.compile_values[name] = value
}

fn (mut prefs Preferences) parse_define(define string) {
	if !define.contains('=') {
		prefs.compile_values[define] = 'true'
		prefs.compile_defines << define
		prefs.compile_defines_all << define
		return
	}
	dname := define.all_before('=')
	dvalue := define.all_after_first('=')
	prefs.compile_values[dname] = dvalue
	prefs.compile_defines_all << dname
	match dvalue {
		'' {}
		else {
			prefs.compile_defines << dname
		}
	}
}

pub fn supported_test_runners_list() string {
	return supported_test_runners.map('`${it}`').join(', ')
}

pub fn (pref &Preferences) should_trace_fn_name(fname string) bool {
	return pref.trace_fns.any(fname.match_glob(it))
}

pub fn (pref &Preferences) should_use_segfault_handler() bool {
	return !('no_segfault_handler' in pref.compile_defines
		|| pref.os in [.wasm32, .wasm32_emscripten])
}
