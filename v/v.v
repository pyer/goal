import os
import v.pref
import v.util
import v.builder
import v.ast
import v.parser
import v.checker
import v.transformer

import v.markused
import v.callgraph
//import v.depgraph
//import v.dotgraph

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
  if prefs.is_verbose {
    println('files: ')
    println(files)
  }

  // Parse files
	//parsed_files []&ast.File
	mut table := ast.new_table()
	table.is_fmt = false
	table.pointer_size = if prefs.m64 { 8 } else { 4 }

  println('Parse files')
	mut parsed_files := parser.parse_files(files, mut table, prefs)
  println('Parse imports')
	parser.parse_imports(mut parsed_files, mut table, prefs)

	table.generic_insts_to_concrete()

  println('Check new')
	mut check := checker.new_checker(table, prefs)
  println('Check files')
	check.check_files(parsed_files)

//	b.comptime.solve_files(parsed_files)

	b.print_warnings_and_errors()
	if check.should_abort {
		error('too many errors/warnings/notices')
    return
	}
	if check.unresolved_fixed_sizes.len > 0 {
		check.update_unresolved_fixed_sizes()
	}
	mut transf := transformer.new_transformer_with_table(table, prefs)
	transf.transform_files(parsed_files)
	table.complete_interface_check()
	if prefs.skip_unused {
		markused.mark_used(mut table, prefs, parsed_files)
	}
	if prefs.show_callgraph {
		callgraph.show(mut table, prefs, parsed_files)
	}

  // Generate C source
  out_name_c := prefs.path[..prefs.path.len - 1] + 'c'
  source := c.gen(parsed_files, mut table, prefs)
  os.write_file_array(out_name_c, source) or { panic(err) }

  // Compile C source
  compiler.cc(out_name_c, prefs)

  util.free_caches()
}
