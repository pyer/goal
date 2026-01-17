import os
import v.pref
import v.util
import v.builder
import v.gen.c
import v.compiler

const v_version = '1.0.1'

fn show_help() {
  println('Usage: v main.v')
}

fn show_version() {
  println(v_version)
}


fn main() {
	unbuffer_stdout()
	args := os.args[1..]

	if args.len == 0 {
    println(v_version)
		return
	}
	prefs := pref.parse_args_and_show_errors()
	if prefs.show_help {
    show_help()
		return
	}
	if prefs.show_version {
    show_version()
		return
	}

	// Construct the V object from command line arguments
	mut b := builder.new_builder(prefs)

	mut files := b.get_builtin_files()
	files << b.get_user_files()
	if b.pref.is_verbose {
		println('files: ')
		println(files)
	}

	b.front_stages(files)!
	b.middle_stages()!

  // Generate C source
	out_name_c := b.pref.path[..b.pref.path.len - 1] + 'c'
	source := c.gen(b.parsed_files, mut b.table, b.pref)
	os.write_file_array(out_name_c, source) or { panic(err) }

  // Compile C source
	compiler.cc(out_name_c, b.pref)

	util.free_caches()
}
