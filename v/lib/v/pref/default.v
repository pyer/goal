// Copyright (c) 2019-2024 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module pref

import os

pub const default_module_path = os.vmodules_dir()

pub fn (mut p Preferences) defines_map_unique_keys() string {
	mut defines_map := map[string]bool{}
	for d in p.compile_defines {
		defines_map[d] = true
	}
	for d in p.compile_defines_all {
		defines_map[d] = true
	}
	keys := defines_map.keys()
	skeys := keys.sorted()
	return skeys.join(',')
}

pub fn (mut p Preferences) fill_with_defaults() {
  p.vexe = os.real_path(os.executable())
	p.vroot = os.dir(p.vexe)
	p.vlib     = os.join_path(p.vroot, 'lib')
	p.vmodules = os.join_path(p.vroot, 'modules')
	p.lookup_path = [ p.vlib, p.vmodules ]
  //println(p.lookup_path)

  println(p.path)
  if p.path.starts_with('.') {
    eprintln('Bad file name, cannot start with .')
    exit(1)
  }

	if p.is_debug {
		p.parse_define('debug')
	}
	p.is_test = p.path.ends_with('_test.v') || p.path.ends_with('_test.vv')
		|| p.path.all_before_last('.v').all_before_last('.').ends_with('_test')
	p.is_vsh = p.path.ends_with('.vsh') || p.raw_vsh_tmp_prefix != ''
	p.is_script = p.is_vsh || p.path.ends_with('.v') || p.path.ends_with('.vv')
	if p.third_party_option == '' {
		p.third_party_option = p.cflags
		$if !windows {
			if !p.third_party_option.contains('-fPIC') {
				p.third_party_option += ' -fPIC'
			}
		}
	}

	final_os := p.os.lower()
	p.parse_define(final_os)

	p.bare_builtin_dir = os.join_path(p.vroot, 'lib', 'builtin', 'linux_bare')
}

pub fn vexe_path() string {
	return os.real_path(os.executable())
}

