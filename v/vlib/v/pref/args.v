module pref

import os.cmdline
import os

pub fn vexe_path() string {
	return os.real_path(os.executable())
}

pub fn parse_args_and_show_errors() (&Preferences) {
	mut res := &Preferences{}
  args := os.args
	$if x64 {
		res.m64 = true // follow V model by default
	}
  res.os = .linux

  res.vexe = os.real_path(os.executable())
	res.vroot = os.dir(res.vexe)
	res.vlib     = os.join_path(res.vroot, 'lib')
	res.vmodules = os.join_path(res.vroot, 'modules')
	res.lookup_path = [ res.vlib, res.vmodules ]

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
			'-check' {
				res.check_only = true
			}
			'-vls-mode' {
				res.is_vls = true
			}
			'-progress' {
				res.is_progress = true
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
			'-Wimpure-v' {
				res.warn_impure_v = true
			}
			'-Wfatal-errors' {
				res.fatal_errors = true
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
			'-json-errors' {
				res.json_errors = true
			}
			'-enable-globals' {
				res.enable_globals = true
			}
			'-force-bounds-checking' {
				res.force_bounds_checking = true
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
			'-run' {
				res.is_run = true
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
			'-check-return' {
				res.is_check_return = true
			}
			'-check-overflow' {
				res.is_check_overflow = true
			}
			else {
        if arg.ends_with('.v') {
          res.path = arg
          res.target = arg[..arg.len - 2]
        } else {
          res.path = arg + '.v'
          res.target = arg
        }
        res.target_c = res.target + '.c'
			}
		}
	}

  if res.path.starts_with('.') {
    eprintln('Bad file name, cannot start with .')
    exit(1)
  }
  if !os.exists(res.path) {
    eprintln("${res.path} is not found")
    exit(1)
  }
  if os.is_dir(res.path) {
    eprintln("${res.path} is not a file")
    exit(1)
  }
	res.is_test = res.path.ends_with('_test.v')

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

	if 'callstack' in res.compile_defines_all {
		res.is_callstack = true
	}
	if 'trace' in res.compile_defines_all {
		res.is_trace = true
	}

	if res.is_debug {
		res.parse_define('debug')
	}
	res.parse_define(res.os.lower())

	return res
}

