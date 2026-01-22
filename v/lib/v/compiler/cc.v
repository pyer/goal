module compiler

import os
import term
import v.pref
import v.util

const c_std = 'c99'

const c_verror_message_marker = 'VERROR_MESSAGE '

const current_os = os.user_os()

const c_compilation_error_title = 'C compilation error'

@[noreturn]
fn verror(s string) {
	util.verror('cgen error', s)
}

fn show_c_compiler_output(ccompiler string, res os.Result) {
	header := '======== Output of the C Compiler (${ccompiler}) ========'
	println(header)
	println(res.output.trim_space())
	println('='.repeat(header.len))
}

fn post_process_c_compiler_output(ccompiler string, res os.Result, pref_ &pref.Preferences) {
	if res.exit_code == 0 {
		return
	}
	for emsg_marker in [c_verror_message_marker, 'error: include file '] {
		if res.output.contains(emsg_marker) {
			emessage := res.output.all_after(emsg_marker).all_before('\n').all_before('\r').trim_right('\r\n')
			verror(emessage)
		}
	}
	if pref_.is_debug {
		eword := 'error:'
		khighlight := highlight_word(eword)
		println(res.output.trim_right('\r\n').replace(eword, khighlight))
	} else {
		if res.output.len < 30 {
			println(res.output)
		} else {
			trimmed_output := res.output.trim_space()
			original_elines := trimmed_output.split_into_lines()
			mlines := 12
			cut_off_limit := if original_elines.len > mlines + 3 { mlines } else { mlines + 3 }
			elines := error_context_lines(trimmed_output, 'error:', 1, cut_off_limit)
			header := '================== ${c_compilation_error_title} (from ${ccompiler}): =============='
			println(header)
			for eline in elines {
				println('cc: ${eline}')
			}
			if original_elines.len != elines.len {
				println('...')
				println('cc: ${original_elines#[-1..][0]}')
				println('(note: the original output was ${original_elines.len} lines long; it was truncated to its first ${elines.len} lines + the last line)')
			}
			println('='.repeat(header.len))
			println('Try passing `-g` when compiling, to see a .v file:line information, that correlates more with the C error.')
			println('(Alternatively, pass `-show-c-output`, to print the full C error message).')
		}
	}
	verror('
==================
C error found. It should never happen, when compiling pure V code.
This is a V compiler bug.')
}

pub struct CcompilerOptions {
pub mut:
	guessed_compiler string
	shared_postfix   string // .so, .dll

	debug_mode bool

	env_cflags  string // prepended *before* everything else
	env_ldflags string // appended *after* everything else

	args         []string // ordinary C options like `-O2`
	wargs        []string // for `-Wxyz` *exclusively*
	pre_args     []string // options that should go before .o_args
	o_args       []string // for `-o target`
	source_args  []string // for `x.tmp.c`
	post_args    []string // options that should go after .o_args
	linker_flags []string // `-lm`
	ldflags      []string // `-labcd' from `v -ldflags "-labcd"`
}

fn ccompiler_options(ccompiler string, pref_ &pref.Preferences) CcompilerOptions {
	mut ccoptions := CcompilerOptions{}

	mut debug_options := ['-g']
	mut optimization_options := ['-O2']
	// arguments for the C compiler
	ccoptions.args = [pref_.cflags]
	ccoptions.ldflags = [pref_.ldflags]
	ccoptions.wargs = [
		'-Wall',
		'-Wextra',
		'-Werror',
		// if anything, these should be a `v vet` warning instead:
		'-Wno-unused-parameter',
		'-Wno-unused',
		'-Wno-type-limits',
		'-Wno-tautological-compare',
		// these cause various issues:
		'-Wno-shadow', // the V compiler already catches this for user code, and enabling this causes issues with e.g. the `it` variable
		'-Wno-int-to-pointer-cast', // gcc version of the above
		'-Wno-trigraphs', // see stackoverflow.com/a/8435413
		'-Wno-missing-braces', // see stackoverflow.com/q/13746033
		'-Wno-enum-conversion', // silences `.dst_factor_rgb = sokol__gfx__BlendFactor__one_minus_src_alpha`
		'-Wno-enum-compare', // silences `if (ev->mouse_button == sokol__sapp__MouseButton__left) {`
		// enable additional warnings:
		'-Wno-unknown-warning', // if a C compiler does not understand a certain flag, it should just ignore it
		'-Wdate-time',
		'-Wduplicated-branches',
		'-Wduplicated-cond',
		'-Winit-self',
		'-Winvalid-pch',
		'-Wjump-misses-init',
		'-Wlogical-op',
		'-Wmultichar',
		'-Wnested-externs',
		'-Wnull-dereference',
		'-Wpacked',
		'-Wpointer-arith',
	]
	ccoptions.debug_mode = pref_.is_debug

	// Add -fwrapv to handle UB overflows
	ccoptions.args << '-fwrapv'

	if ccoptions.debug_mode {
		debug_options = ['-g']
	}
	optimization_options = ['-O3']
	mut have_flto := true
	if have_flto {
		optimization_options << '-flto'
	}

	if ccoptions.debug_mode {
		ccoptions.args << debug_options
	}
	if pref_.is_prod {
		// don't warn for vlib tests
		if !pref_.no_prod_options {
			ccoptions.args << optimization_options
		}
	}
	if pref_.is_prod && !ccoptions.debug_mode {
		// sokol and other C libraries that use asserts
		// have much better performance when NDEBUG is defined
		// See also http://www.open-std.org/jtc1/sc22/wg14/www/docs/n1256.pdf
		ccoptions.args << '-DNDEBUG'
		ccoptions.args << '-DNO_DEBUGGING' // for BDWGC
	}
	if pref_.sanitize {
		ccoptions.args << '-fsanitize=leak'
	}

	ccoptions.shared_postfix = '.so'
	if pref_.is_bare {
		ccoptions.args << '-fno-stack-protector'
		ccoptions.args << '-ffreestanding'
		ccoptions.linker_flags << '-static'
		ccoptions.linker_flags << '-nostdlib'
	}

	ccoptions.wargs << '-Werror=implicit-function-declaration'

	// The C file we are compiling
	ccoptions.source_args << os.quoted_path(pref_.target_c)
  /*
	cflags := get_os_cflags()

	if pref_.build_mode != .build_module {
		only_o_files := cflags.c_options_only_object_files()
		ccoptions.o_args << only_o_files
	}

	defines, others, libs := cflags.defines_others_libs()
	ccoptions.pre_args << defines
	ccoptions.pre_args << others
	ccoptions.linker_flags << libs
	// Without these libs compilation will fail on Linux
	if !pref_.is_bare && pref_.build_mode != .build_module
		&& pref_.os in [.linux, .freebsd, .openbsd, .netbsd, .dragonfly, .solaris, .haiku] {
		if pref_.os in [.freebsd, .netbsd] {
			// Free/NetBSD: backtrace needs execinfo library while linking, also execinfo depends on elf.
			ccoptions.linker_flags << '-lexecinfo'
			ccoptions.linker_flags << '-lelf'
		}
	}
  */
	ccoptions.source_args << ['-std=${c_std}', '-D_DEFAULT_SOURCE']
	$if trace_ccoptions ? {
		println('>>> setup_ccompiler_options ccoptions: ${ccoptions}')
	}
  return ccoptions
}

fn compile_args(ccoptions CcompilerOptions, pref_ &pref.Preferences) []string {
	mut all := []string{}
	all << ccoptions.env_cflags
	if pref_.is_cstrict {
		all << ccoptions.wargs
	}
	all << ccoptions.args
	all << ccoptions.o_args
	all << ccoptions.pre_args
	all << ccoptions.source_args
	all << ccoptions.post_args
	return all
}

fn linker_args(ccoptions CcompilerOptions, pref_ &pref.Preferences) []string {
	mut all := []string{}
	// in `build-mode`, we do not need -lxyz flags, since we are
	// building an (.o) object file, that will be linked later.
	if pref_.build_mode != .build_module {
		all << ccoptions.linker_flags
		all << ccoptions.env_ldflags
		all << ccoptions.ldflags
	}
	return all
}


fn highlight_word(keyword string) string {
	return if term.can_show_color_on_stdout() { term.red(keyword) } else { keyword }
}

fn error_context_lines(text string, keyword string, before int, after int) []string {
	khighlight := highlight_word(keyword)
	mut eline_idx := -1
	mut lines := text.split_into_lines()
	for idx, eline in lines {
		if eline.contains(keyword) {
			lines[idx] = lines[idx].replace(keyword, khighlight)
			if eline_idx == -1 {
				eline_idx = idx
			}
		}
	}
	idx_s := if eline_idx - before >= 0 { eline_idx - before } else { 0 }
	idx_e := if idx_s + after < lines.len { idx_s + after } else { lines.len }
	return lines[idx_s..idx_e]
}


pub fn cc(pref_ &pref.Preferences) {
  ccompiler := 'gcc'

	mut tried_compilation_commands := []string{}
	original_pwd := os.getwd()

		// try to compile with the chosen compiler
		// if compilation fails, retry again with another
		mut ccoptions := ccompiler_options(ccompiler, pref_)
	  if os.is_dir(pref_.target) {
		  verror('${os.quoted_path(pref_.target)} is a directory')
	  }
	  ccoptions.o_args << '-o ${os.quoted_path(pref_.target)}'

		if pref_.build_mode == .build_module {
			ccoptions.pre_args << '-c'
		}
		//v.handle_usecache(vexe)
	  mut all_args := []string{}
	  all_args << compile_args(ccoptions, pref_)
	  all_args << linker_args(ccoptions, pref_)
		//dump_c_options(all_args)
		str_args := all_args.join(' ').replace('\n', ' ')
		mut cmd := '${os.quoted_path(ccompiler)} ${str_args}'

		//os.chdir(vdir) or {}
		tried_compilation_commands << cmd
  	if pref_.is_verbose || pref_.show_cc {
	  	println('> C compiler cmd: ${cmd}')
	  }

		// Run
		ccompiler_label := 'C gcc'
		util.timing_start(ccompiler_label)
		res := os.execute(cmd)
		util.timing_measure(ccompiler_label)
		if pref_.show_c_output {
			show_c_compiler_output(ccompiler, res)
		}
		os.chdir(original_pwd) or {}
		if res.exit_code == 127 {
				verror('C compiler error, while attempting to run: \n' +
					'-----------------------------------------------------------\n' + '${cmd}\n' +
					'-----------------------------------------------------------\n' +
					'Probably your C compiler is missing. \n' +
					'Please reinstall it, or make it available in your PATH.\n\n')
		}
		post_process_c_compiler_output(ccompiler, res, pref_)
		// Print the C command
		if pref_.is_verbose {
			println('${ccompiler}')
			println('=========\n')
		}

  if !pref_.keepc {
    os.rm(pref_.target_c) or {}
  }
}

