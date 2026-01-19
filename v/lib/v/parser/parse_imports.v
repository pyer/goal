module parser

import os
import v.token
import v.pref
import v.errors
import v.util
import v.ast
/*
import v.vmod
import v.checker
import v.transformer
import v.comptime
import v.markused
import v.callgraph
import v.dotgraph
*/
import v.depgraph

// TODO: try to merge this & util.module functions to create a
// reliable multi use function. see comments in util/module.v
fn find_module_path(mod string, fpath string, module_search_paths []string) !string {
  // println("find_module_path( ${mod}, ${fpath}, ${module_search_paths})")
  /*
	// support @VROOT/v.mod relative paths:
	mut mcache := vmod.get_cache()
	vmod_file_location := mcache.get_by_file(fpath)
	mod_path := mod.replace('.', os.path_separator)
	mut module_lookup_paths := []string{}
	if vmod_file_location.vmod_file.len != 0
		&& vmod_file_location.vmod_folder !in module_search_paths {
		module_lookup_paths << vmod_file_location.vmod_folder
	}
*/
	mut module_lookup_paths := []string{}
	module_lookup_paths << module_search_paths
	module_lookup_paths << os.getwd()

/*
	// go up through parents looking for modules a folder.
	// we need a proper solution that works most of the time. look at vdoc.get_parent_mod
	if fpath.contains(os.path_separator + 'modules' + os.path_separator) {
		parts := fpath.split(os.path_separator)
		for i := parts.len - 2; i >= 0; i-- {
			if parts[i] == 'modules' {
				module_lookup_paths << parts[0..i + 1].join(os.path_separator)
				break
			}
		}
	}
*/

	mod_path := mod.replace('.', os.path_separator)
  //println("find_module_path( ${mod_path}, ${module_lookup_paths})")
	for search_path in module_lookup_paths {
		try_path := os.join_path(search_path, mod_path)
		if os.is_dir(try_path) {
			return try_path
		}
	}
	// look up through parents
	path_parts := fpath.split(os.path_separator)
	for i := path_parts.len - 2; i > 0; i-- {
		p1 := path_parts[0..i].join(os.path_separator)
		try_path := os.join_path(p1, mod_path)
		if os.is_dir(try_path) {
			return try_path
		}
	}
	return error('module "${mod}" not found')
}

/*
	// Note: changes in mod `builtin` force invalidation of every other .v file
	mod_invalidates_paths map[string][]string // changes in mod `os`, invalidate only .v files, that do `import os`
	mod_invalidates_mods  map[string][]string // changes in mod `os`, force invalidation of mods, that do `import os`
	path_invalidates_mods map[string][]string // changes in a .v file from `os`, invalidates `os`
*/
fn error_with_pos(s string, fpath string, pos token.Pos) errors.Error {
		util.show_compiler_message('parse import error:', pos: pos, file_path: fpath, message: s)
		exit(1)
}

fn v_files_from_dir(dir string) []string {
	if !os.exists(dir) {
		util.verror('parse error', "${dir} doesn't exist")
	} else if !os.is_dir(dir) {
		util.verror('parse error', "${dir} isn't a directory!")
	}

	ret := os.ls(dir) or { panic(err) }
  return ret
}

// graph of all imported modules
fn import_graph(parsed_files []&ast.File) &depgraph.DepGraph {
	builtins := util.builtin_module_parts.clone()
	mut graph := depgraph.new_dep_graph()
	for p in parsed_files {
		// eprintln('p.path: $p.path')
		mut deps := []string{}
		if p.mod.name !in builtins {
			deps << 'builtin'
		}
		for m in p.imports {
			if m.mod == p.mod.name {
				continue
			}
			deps << m.mod
		}
		graph.add(p.mod.name, deps)
	}
	return graph
}


// parse all deps from already parsed files
//pub fn (mut p Parser) parse_imports(mut parsed_files []&ast.File, mut table ast.Table, pref_ &pref.Preferences) []&ast.File {
pub fn parse_imports(mut all_parsed_files []&ast.File, mut table ast.Table, pref_ &pref.Preferences) {
//  mut all_parsed_files := files.clone()
//  println("parse_imports")
//  println(all_parsed_files.len)
	util.timing_start(@METHOD)
	defer {
		util.timing_measure(@METHOD)
	}
	mut done_imports := []string{}

	// TODO: (joe): decide if this is correct solution.
	// in the case of building a module, the actual module files
	// are passed via cmd line, so they have already been parsed
	// by this stage. note that if one files from a module was
	// parsed (but not all of them), then this will cause a problem.
	// we could add a list of parsed files instead, but I think
	// there is a better solution all around, I will revisit this.
	// NOTE: there is a very similar occurrence with the way
	// internal module test's work, and this was the reason there
	// were issues with duplicate declarations, so we should sort
	// that out in a similar way.
	for file in all_parsed_files {
		if file.mod.name != 'main' && file.mod.name !in done_imports {
			done_imports << file.mod.name
		}
	}
	// Note: files is appended in the loop,
	// so we can not use the shorter `for in` form.
	for i := 0; i < all_parsed_files.len; i++ {
		ast_file := all_parsed_files[i]
/*
		path_invalidates_mods[ast_file.path] << ast_file.mod.name
		if ast_file.mod.name != 'builtin' {
			mod_invalidates_paths['builtin'] << ast_file.path
			mod_invalidates_mods['builtin'] << ast_file.mod.name
		}
*/
		for imp in ast_file.imports {
			mod := imp.mod
//			mod_invalidates_paths[mod] << ast_file.path
//			mod_invalidates_mods[mod] << ast_file.mod.name
			if mod == 'builtin' {
				all_parsed_files[i].errors << error_with_pos('cannot import module "builtin"', ast_file.path, imp.pos)
				break
			}
			if mod in done_imports {
				continue
			}
			import_path := find_module_path(mod, ast_file.path, pref_.lookup_path) or {
				// v.parsers[i].error_with_token_index('cannot import module "$mod" (not found)', v.parsers[i].import_ast.get_import_tok_idx(mod))
				// break
				all_parsed_files[i].errors << error_with_pos('cannot import module "${mod}" (not found)', ast_file.path, imp.pos)
				break
			}
			raw_files := v_files_from_dir(import_path)
	    v_files := pref_.should_compile_filtered_files(import_path, raw_files)
			if v_files.len == 0 {
				// v.parsers[i].error_with_token_index('cannot import module "$mod" (no .v files in "$import_path")', v.parsers[i].import_ast.get_import_tok_idx(mod))
				all_parsed_files[i].errors << error_with_pos('cannot import module "${mod}" (no .v files in "${import_path}")', ast_file.path, imp.pos)
				continue
			}
			// eprintln('>> ast_file.path: $ast_file.path , done: $done_imports, `import $mod` => $v_files')
			// Add all imports referenced by these libs
			parsed_files := parse_files(v_files, mut table, pref_)
			for file in parsed_files {
				mut name := file.mod.name
				if name == '' {
					name = file.mod.short_name
				}
				sname := name.all_after_last('.')
				smod := mod.all_after_last('.')
				if sname != smod {
					msg := 'bad module definition: ${ast_file.path} imports module "${mod}" but ${file.path} is defined as module `${name}`'
					all_parsed_files[i].errors << error_with_pos(msg, ast_file.path, imp.pos)
				}
			}
			all_parsed_files << parsed_files
			done_imports << mod
//      println("parsed ${all_parsed_files}")
//      println(done_imports)
		}
	}

  // Resolve dependencies
	graph := import_graph(all_parsed_files)
	if pref_.is_verbose {
		eprintln(graph.display())
	}
	deps_resolved := graph.resolve()
	if pref_.is_verbose {
		eprintln('------ resolved dependencies graph: ------')
		eprintln(deps_resolved.display())
		eprintln('------------------------------------------')
	}
	if pref_.show_depgraph {
		depgraph.show(deps_resolved, pref_.path)
	}
	cycles := deps_resolved.display_cycles()
	if cycles.len > 1 {
		util.verror('parse error', 'error: import cycle detected between the following modules: \n' + cycles)
	}
	mut mods := []string{}
	for node in deps_resolved.nodes {
		mods << node.name
	}
	if pref_.is_verbose {
		eprintln('------ imported modules: ------')
		eprintln(mods.str())
		eprintln('-------------------------------')
	}
	unsafe {
		mut reordered_parsed_files := []&ast.File{}
		for m in mods {
			for pf in all_parsed_files {
				if m == pf.mod.name {
					reordered_parsed_files << pf
					// eprintln('pf.mod.name: $pf.mod.name | pf.path: $pf.path')
				}
			}
		}
		table.modules = mods
		all_parsed_files = reordered_parsed_files
	}
}

