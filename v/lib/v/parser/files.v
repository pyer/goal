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
		if file.ends_with('.v') && !file.ends_with('_test.v') {
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

pub fn get_source_file(pref_ &pref.Preferences) []string {
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

