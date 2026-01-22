import os
import v.pref
import v.util
import v.ast
import v.parser
import v.checker
import v.comptime
import v.transformer

import v.markused
import v.callgraph
//import v.depgraph
//import v.dotgraph

import v.gen.c
import v.compiler

const v_version = '1.0.2'

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

  println('Building ${prefs.path} => ${prefs.target_c} => ${prefs.target}')

  // Construct the V object from command line arguments
  println('Get builtin and user files')
  mut files := parser.get_builtin_files(prefs)
  files << parser.get_prelude_files(prefs)
  files << parser.get_source_file(prefs)
  if prefs.is_verbose {
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

  println('Check files')
  mut check := checker.new_checker(table, prefs)
  check.check_files(parsed_files)

  mut ct := comptime.new_comptime_with_table(table, prefs)
  ct.solve_files(parsed_files)

//  b.print_warnings_and_errors()
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
  source := c.gen(mut table, prefs, parsed_files)
  os.write_file_array(prefs.target_c, source) or { panic(err) }

  // Compile C source
  compiler.cc(prefs)

  util.free_caches()
  /*
  if prefs.is_test {
    os.execute(prefs.target)
    os.rm(prefs.target)
  }
  */
}
