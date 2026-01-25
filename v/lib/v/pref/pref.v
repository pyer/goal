module pref

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

pub enum ColorOutput {
	auto
	always
	never
}

pub const supported_test_runners = ['normal', 'simple', 'tap', 'dump', 'teamcity']

@[heap; minify]
pub struct Preferences {
pub mut:
	arch                Arch
	os                  OS // the OS to compile for
	build_mode          BuildMode
	// verbosity           VerboseLevel
	is_verbose         bool
	is_test            bool   // `v test string_test.v`
	is_prod            bool   // use "-O3"
	no_prod_options    bool   // `-no-prod-options`, means do not pass any optimization flags to the C compilation, while still allowing the user to use for example `-cflags -Os` to pass custom ones
  is_run             bool // run the executable after compilation
	is_debug           bool // turned on by -g/-debug or -cg/-cdebug, it tells v to pass -g to the C backend compiler.
	show_asserts       bool // `VTEST_SHOW_ASSERTS=1 v file_test.v` will show details about the asserts done by a test file. Also activated for `-stats` and `-show-asserts`.
	show_timings       bool // show how much time each compiler stage took
	show_version       bool // -v, -V, -version or --version was passed
	show_help          bool // -?, -h, -help or --help was passed
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
	show_callgraph         bool   // -show-callgraph, print the program callgraph, in a Graphviz DOT format to stdout
	show_depgraph          bool   // -show-depgraph, print the program module dependency graph, in a Graphviz DOT format to stdout
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
	no_closures      bool   // Produce a compile time error, if a closure was generated for any reason (an implicit receiver method was stored, or an explicit `fn [captured]()`).
	lookup_path      []string
	prealloc         bool
	vexe             string
	vroot            string
	vlib             string // absolute path to the lib folder
	vmodules         string // absolute path to the modules folder
	path             string // Path to the source file to compile
	target_c         string // Name of the generated C source
	target           string // Name of the generated executable
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

	check_only        bool // when true, just parse the files and run the checker
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
	//
	is_vls        bool
	json_errors   bool // -json-errors, for VLS and other tools
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
