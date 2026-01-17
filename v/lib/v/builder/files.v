// Copyright (c) 2019-2024 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module builder

import os
import v.pref
import v.util

pub fn (v Builder) get_builtin_files() []string {
	if v.pref.no_builtin {
		v.log('v.pref.no_builtin is true, get_builtin_files == []')
		return []
	}
	v.log('v.pref.lookup_path: ${v.pref.lookup_path}')
	// Lookup for built-in folder in lookup path.
	// Assumption: `builtin/` folder implies usable implementation of builtin
	for location in v.pref.lookup_path {
		if os.exists(os.join_path(location, 'builtin')) {
			mut builtin_files := []string{}
			builtin_files << v.v_files_from_dir(os.join_path(location, 'builtin'))
			if v.pref.is_bare {
				builtin_files << v.v_files_from_dir(v.pref.bare_builtin_dir)
			}
			return builtin_files
		}
	}
	// Panic. We couldn't find the folder.
	verror('`builtin/` not included on module lookup path.\nDid you forget to add lib to the path? (Use @vlib for default lib)')
}

pub fn (v &Builder) get_user_files() []string {
	if v.pref.path in ['lib/builtin', 'lib/strconv', 'lib/strings', 'lib/hash']
		|| v.pref.path.ends_with('lib/builtin') {
		// This means we are building a builtin module with `v build-module lib/strings` etc
		// get_builtin_files() has already added the files in this module,
		// do nothing here to avoid duplicate definition errors.
		v.log('Skipping user files.')
		return []
	}
	mut dir := v.pref.path
	v.log('get_v_files(${dir})')
	// Need to store user files separately, because they have to be added after
	// libs, but we dont know	which libs need to be added yet
	mut user_files := []string{}
	// See cmd/tools/preludes/README.md for more info about what preludes are
	mut preludes_path := os.join_path(v.pref.vroot, 'lib', 'v', 'preludes')
	if v.pref.trace_calls {
		user_files << os.join_path(preludes_path, 'trace_calls.v')
	}
	if v.pref.is_test {
		user_files << os.join_path(preludes_path, 'test_runner.c.v')
		//
		mut v_test_runner_prelude := v.pref.test_runner
		if v_test_runner_prelude == '' {
			v_test_runner_prelude = 'normal'
		}
		if !v_test_runner_prelude.contains('/') && !v_test_runner_prelude.contains('\\')
			&& !v_test_runner_prelude.ends_with('.v') {
			v_test_runner_prelude = os.join_path(preludes_path, 'test_runner_${v_test_runner_prelude}.v')
		}
		if !os.is_file(v_test_runner_prelude) || !os.is_readable(v_test_runner_prelude) {
			eprintln('test runner error: File ${v_test_runner_prelude} should be readable.')
			verror('the supported test runners are: ${pref.supported_test_runners_list()}')
		}
		user_files << v_test_runner_prelude
	}
	if v.pref.is_test && v.pref.show_asserts {
		user_files << os.join_path(preludes_path, 'tests_with_stats.v')
	}
	is_test := v.pref.is_test
	mut is_internal_module_test := false
	if is_test {
		tcontent := util.read_file(dir) or { verror('${dir} does not exist') }
		slines := tcontent.split_into_lines()
		for sline in slines {
			line := sline.trim_space()
			if line.len > 2 {
				if line[0] == `/` && line[1] == `/` {
					continue
				}
				if line.starts_with('module ') {
					is_internal_module_test = true
					break
				}
			}
		}
	}
	if is_internal_module_test {
		// v volt/slack_test.v: compile all .v files to get the environment
		single_test_v_file := os.real_path(dir)
		if v.pref.is_verbose {
			v.log('> Compiling an internal module _test.v file ${single_test_v_file} .')
			v.log('> That brings in all other ordinary .v files in the same module too .')
		}
		user_files << single_test_v_file
		dir = os.dir(single_test_v_file)
	}
	v.add_file_or_dir(mut user_files, dir)
	for f in v.pref.file_list {
		file := f.trim_space()
		if file.len > 0 {
			v.add_file_or_dir(mut user_files, file)
		}
	}
	if user_files.len == 0 {
		println('No input .v files')
		exit(1)
	}
	if v.pref.is_verbose {
		v.log('user_files: ${user_files}')
	}
	return user_files
}

fn (v &Builder) add_file_or_dir(mut user_files []string, dir string) {
	does_exist := os.exists(dir)
	if !does_exist {
		verror("${dir} doesn't exist")
	}
	is_real_file := does_exist && !os.is_dir(dir)
	if is_real_file && dir.ends_with('.v') {
		single_v_file := dir
		// Just compile one file and get parent dir
		user_files << single_v_file
		if v.pref.is_verbose {
			v.log('> add one file: "${single_v_file}"')
		}
	} else if os.is_dir(dir) {
		if v.pref.is_verbose {
			v.log('> add all .v files from directory "${dir}" ...')
		}
		// Add .v files from the directory being compiled
		user_files << v.v_files_from_dir(dir)
	} else {
		println('usage: `v file.v` or `v directory`')
		ext := os.file_ext(dir)
		println('unknown file extension `${ext}`')
		exit(1)
	}
}
