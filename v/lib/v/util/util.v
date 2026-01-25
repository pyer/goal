// Copyright (c) 2019-2024 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module util

import os
import term
import time
import runtime

// math.bits is needed by strconv.ftoa
pub const builtin_module_parts = ['math.bits', 'strconv', 'strconv.ftoa', 'strings',
	'builtin', 'builtin.closure', 'builtin.overflow']

pub const external_module_dependencies_for_tool = {
	'vdoc': ['markdown']
}

pub const nr_jobs = runtime.nr_jobs()

pub fn module_is_builtin(mod string) bool {
	return mod in builtin_module_parts
}

//@[direct_array_access]
pub fn tabs(n int) string {
  return '\t'.repeat(n)
//	return if n >= 0 && n < const_tabs.len { const_tabs[n] } else { '\t'.repeat(n) }
}

pub const stable_build_time = get_build_time()
// get_build_time returns the current build UTC time.
pub fn get_build_time() time.Time {
	return time.utc()
}

// set_vroot_folder sets the VEXE env variable to the location of the V executable
pub fn set_vroot_folder(vroot_path string) {
	// Preparation for the compiler module:
	// VEXE env variable is needed so that compiler.vexe_path() can return it
	// later to whoever needs it. Note: guessing is a heuristic, so only try to
	// guess the V executable name, if VEXE has not been set already.
	os.setenv('VEXE', os.real_path(os.join_path_single(vroot_path, 'v')), true)
}

// is_escape_sequence returns `true` if `c` is considered a valid escape sequence denoter.
@[inline]
pub fn is_escape_sequence(c u8) bool {
	return c in [`x`, `u`, `e`, `n`, `r`, `t`, `v`, `a`, `f`, `b`, `\\`, `\``, `$`, `@`, `?`, `{`,
		`}`, `'`, `"`, `U`]
}

@[if trace_launch_tool ?]
fn tlog(s string) {
	ts := time.now().format_ss_micro()
	eprintln('${term.yellow(ts)} ${term.gray(s)}')
}

@[noreturn]
fn cmd_system(cmd string) {
	res := os.system(cmd)
	if res != 0 {
		tlog('> error ${res}, while executing: ${cmd}')
	}
	exit(res)
}

// Note: should_recompile_tool/4 compares unix timestamps that have 1 second resolution
// That means that a tool can get recompiled twice, if called in short succession.
// TODO: use a nanosecond mtime timestamp, if available.
pub fn should_recompile_tool(vexe string, tool_source string, tool_name string, tool_exe string) bool {
	if os.is_dir(tool_source) {
		source_files := os.walk_ext(tool_source, '.v')
		mut newest_sfile := ''
		mut newest_sfile_mtime := i64(0)
		for sfile in source_files {
			mtime := os.file_last_mod_unix(sfile)
			if mtime > newest_sfile_mtime {
				newest_sfile_mtime = mtime
				newest_sfile = sfile
			}
		}
		single_file_recompile := should_recompile_tool(vexe, newest_sfile, tool_name,
			tool_exe)
		// eprintln('>>> should_recompile_tool: tool_source: $tool_source | $single_file_recompile | $newest_sfile')
		return single_file_recompile
	}
	// TODO: Caching should be done on the `vlib/v` level.
	mut should_compile := false
	if !os.exists(tool_exe) {
		should_compile = true
	} else {
		mtime_vexe := os.file_last_mod_unix(vexe)
		mtime_tool_exe := os.file_last_mod_unix(tool_exe)
		mtime_tool_source := os.file_last_mod_unix(tool_source)
		if mtime_tool_exe <= mtime_vexe {
			// v was recompiled, maybe after v up ...
			// rebuild the tool too just in case
			should_compile = true
			if tool_name == 'vself' || tool_name == 'vup' {
				// The purpose of vself/up is to update and recompile v itself.
				// After the first 'v self' execution, v will be modified, so
				// then a second 'v self' will detect, that v is newer than the
				// vself executable, and try to recompile vself/up again, which
				// will slow down the next v recompilation needlessly.
				should_compile = false
			}
		}
		if mtime_tool_exe <= mtime_tool_source {
			// the user changed the source code of the tool, or git updated it:
			should_compile = true
		}
		// GNU Guix and possibly other environments, have bit for bit reproducibility in mind,
		// including filesystem attributes like modification times, so they set the modification
		// times of executables to a small number like 0, 1 etc. In this case, we should not
		// recompile even if other heuristics say that we should. Users in such environments,
		// have to explicitly do: `v cmd/tools/vfmt.v`, and/or install v from source, and not
		// use the system packaged one, if they desire to develop v itself.
		if mtime_vexe < 1024 && mtime_tool_exe < 1024 {
			should_compile = false
		}
	}
	return should_compile
}

fn tool_source2name_and_exe(tool_source string) (string, string) {
	sfolder := os.dir(tool_source)
	tool_name := os.base(tool_source).replace('.v', '')
	tool_exe := os.join_path_single(sfolder, path_of_executable(tool_name))
	return tool_name, tool_exe
}

pub fn quote_path(s string) string {
	return os.quoted_path(s)
}

pub fn args_quote_paths(args []string) string {
	return args.map(quote_path(it)).join(' ')
}

pub fn path_of_executable(path string) string {
	$if windows {
		return path + '.exe'
	}
	return path
}

@[heap]
struct SourceCache {
mut:
	sources map[string]string
}

@[unsafe]
pub fn cached_read_source_file(path string) !string {
	mut static cache := &SourceCache(unsafe { nil })
	if cache == unsafe { nil } {
		cache = &SourceCache{}
	}

	$if trace_cached_read_source_file ? {
		println('cached_read_source_file            ${path}')
	}
	if path == '' {
		unsafe { cache.sources.free() }
		unsafe { free(cache) }
		cache = &SourceCache(unsafe { nil })
		return error('memory source file cache cleared')
	}

	// eprintln('>> cached_read_source_file path: $path')
	if res := cache.sources[path] {
		// eprintln('>> cached')
		$if trace_cached_read_source_file_cached ? {
			println('cached_read_source_file     cached ${path}')
		}
		return res
	}
	// eprintln('>> not cached | cache.sources.len: $cache.sources.len')
	$if trace_cached_read_source_file_not_cached ? {
		println('cached_read_source_file not cached ${path}')
	}
	raw_text := os.read_file(path) or { return error('failed to open ${path}') }
	res := skip_bom(raw_text)
	cache.sources[path] = res
	return res
}

pub fn replace_op(s string) string {
	return match s {
		'+' { '_plus' }
		'-' { '_minus' }
		'*' { '_mult' }
		'/' { '_div' }
		'%' { '_mod' }
		'<' { '_lt' }
		'>' { '_gt' }
		'==' { '_eq' }
		else { '' }
	}
}

@[inline]
pub fn strip_mod_name(name string) string {
	return name.all_after_last('.')
}

@[inline]
pub fn strip_main_name(name string) string {
	return name.replace('main.', '')
}

@[inline]
pub fn no_dots(s string) string {
	return s.replace('.', '__')
}

const map_prefix = 'map[string]'

// no_cur_mod - removes cur_mod. prefix from typename,
// but *only* when it is at the start, i.e.:
// no_cur_mod('vproto.Abdcdef', 'proto') == 'vproto.Abdcdef'
// even though proto. is a substring
pub fn no_cur_mod(typename string, cur_mod string) string {
	mut res := typename
	mod_prefix := cur_mod + '.'
	has_map_prefix := res.starts_with(map_prefix)
	if has_map_prefix {
		res = res.replace_once(map_prefix, '')
	}
	no_symbols := res.trim_left('&[]')
	should_shorten := no_symbols.starts_with(mod_prefix)
	if should_shorten {
		res = res.replace_once(mod_prefix, '')
	}
	if has_map_prefix {
		res = map_prefix + res
	}
	return res
}

pub fn recompile_file(vexe string, file string) {
	cmd := '${os.quoted_path(vexe)} ${os.quoted_path(file)}'
	$if trace_recompilation ? {
		println('recompilation command: ${cmd}')
	}
	recompile_result := os.system(cmd)
	if recompile_result != 0 {
		eprintln('could not recompile ${file}')
		exit(2)
	}
}

// get_vtmp_folder returns the path to a folder, that is writable to V programs,
// and specific to the user. It can be overridden by setting the env variable `VTMP`.
pub fn get_vtmp_folder() string {
	return os.vtmp_dir()
}

// free_caches knows about all `util` caches and makes sure that they are freed
// if you add another cached unsafe function using static, do not forget to add
// a mechanism to clear its cache, and call it here.
pub fn free_caches() {
	unsafe {
		cached_file2sourcelines('')
		cached_read_source_file('') or { '' }
	}
}

pub fn read_file(file_path string) !string {
	return unsafe { cached_read_source_file(file_path) }
}
