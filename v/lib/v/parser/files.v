module parser

import os
import v.pref
import v.util

fn v_files_from_dir(dir string) []string {
	if !os.exists(dir) {
		util.verror('parse error', "${dir} doesn't exist")
	} else if !os.is_dir(dir) {
		util.verror('parse error', "${dir} isn't a directory!")
	}

	files := os.ls(dir) or { panic(err) }
	mut v_files := []string{}
	files_loop: for file in files {
		if file.ends_with('.v') {
      v_files << os.join_path(dir, file)
		}
  }
  return v_files
}

pub fn get_builtin_files(pref_ &pref.Preferences) []string {
	// Lookup for built-in folder in lookup path.
	// Assumption: `builtin/` folder implies usable implementation of builtin
	if os.exists(os.join_path(pref_.vroot, 'builtin')) {
			mut builtin_files := []string{}
			builtin_files << v_files_from_dir(os.join_path(pref_.vroot, 'builtin'))
			return builtin_files
	}
	return []
}

pub fn get_prelude_files(pref_ &pref.Preferences) []string {
	// Need to store user files separately, because they have to be added after
	// libs, but we dont know	which libs need to be added yet
	mut user_files := []string{}
	// See cmd/tools/preludes/README.md for more info about what preludes are
	mut preludes_path := os.join_path(pref_.vroot, 'lib', 'v', 'preludes')
	if pref_.trace_calls {
		user_files << os.join_path(preludes_path, 'trace_calls.v')
	}
	if pref_.is_test {
		user_files << os.join_path(preludes_path, 'test_runner.c.v')
		//
		mut v_test_runner_prelude := pref_.test_runner
		if v_test_runner_prelude == '' {
			v_test_runner_prelude = 'normal'
		}
		if !v_test_runner_prelude.contains('/') && !v_test_runner_prelude.contains('\\')
			&& !v_test_runner_prelude.ends_with('.v') {
			v_test_runner_prelude = os.join_path(preludes_path, 'test_runner_${v_test_runner_prelude}.v')
		}
		if !os.is_file(v_test_runner_prelude) || !os.is_readable(v_test_runner_prelude) {
			eprintln('test runner error: File ${v_test_runner_prelude} should be readable.')
			eprintln('the supported test runners are: ${pref.supported_test_runners_list()}')
      exit(1)
		}
		user_files << v_test_runner_prelude
	}
	if pref_.is_test && pref_.show_asserts {
		user_files << os.join_path(preludes_path, 'tests_with_stats.v')
	}
  /*
	is_test := pref_.is_test
	mut is_internal_module_test := false
	if is_test {
		tcontent := util.read_file(dir) or { util.verror('test prelude', '${dir} does not exist') }
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
		if pref_.is_verbose {
			println('> Compiling an internal module _test.v file ${single_test_v_file} .')
			println('> That brings in all other ordinary .v files in the same module too .')
		}
		user_files << single_test_v_file
		dir = os.dir(single_test_v_file)
	}
  */
	return user_files
}

pub fn get_source_file(pref_ &pref.Preferences) []string {
/*
	if pref_.path in ['lib/builtin', 'lib/strconv', 'lib/strings', 'lib/hash']
		|| pref_.path.ends_with('lib/builtin') {
		// This means we are building a builtin module with `v build-module lib/strings` etc
		// get_builtin_files() has already added the files in this module,
		// do nothing here to avoid duplicate definition errors.
		println('Skipping user files.')
		return []
	}
*/
	mut files := []string{}
	mut src := pref_.path
  if !os.exists(src) {
    eprintln("${src} not found")
    exit(1)
  }
  if os.is_dir(src) {
    eprintln("${src} is not a file")
    exit(1)
  }
  if !src.ends_with('.v') {
    eprintln("${src} is not a source file")
    exit(1)
  }
	files << src
  return files
}

