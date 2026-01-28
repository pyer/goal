module parser

import os
import hash.fnv1a

import v.scanner
import v.ast
import v.token
import v.pref
import v.util
import v.errors
//import strings

const normalised_working_folder = (os.real_path(os.getwd()) + os.path_separator).replace('\\', '/')

pub fn (mut p Parser) set_path(path string) {
	p.file_path = path
	p.file_base = os.base(path)
	p.file_display_path = os.real_path(p.file_path).replace_once(normalised_working_folder,
		'').replace('\\', '/')
	p.inside_vlib_file = os.dir(path).contains('lib')

	hash := fnv1a.sum64_string(path)
	p.unique_prefix = hash.hex_full()

	p.file_backend_mode = .v
	before_dot_v := path.all_before_last('.v') // also works for .vv and .vsh
	language := before_dot_v.all_after_last('.')
	language_with_underscore := before_dot_v.all_after_last('_')
	if language == before_dot_v && language_with_underscore == before_dot_v {
		return
	}
	actual_language := if language == before_dot_v { language_with_underscore } else { language }
	match actual_language {
		'c' {
			p.file_backend_mode = .c
		}
		'js' {
			p.file_backend_mode = .js
		}
		else {
			arch := pref.arch_from_string(actual_language) or { pref.Arch._auto }
			p.file_backend_mode = ast.pref_arch_to_table_language(arch)
			if arch == ._auto {
				p.file_backend_mode = .v
			}
		}
	}
}

fn should_skip_vls_file(pref_ &pref.Preferences, path string) bool {
	if !pref_.is_vls {
		return false
	}
	if pref_.line_info != '' {
		project_dir := if os.is_dir(pref_.path) {
			os.real_path(pref_.path)
		} else {
			os.real_path(os.dir(pref_.linfo.path))
		}
		return !os.real_path(path).starts_with(project_dir)
	}
	return path != pref_.path
}

pub fn parse_file(path string, mut table ast.Table, comments_mode scanner.CommentsMode, pref_ &pref.Preferences) &ast.File {
	// Note: when comments_mode == .toplevel_comments,
	// the parser gives feedback to the scanner about toplevel statements, so that the scanner can skip
	// all the tricky inner comments. This is needed because we do not have a good general solution
	// for handling them, and should be removed when we do (the general solution is also needed for vfmt)
	$if trace_parse_file ? {
		eprintln('> ${@MOD}.${@FN} comments_mode: ${comments_mode:-20} | path: ${path}')
	}
	mut file_idx := i16(table.filelist.index(path))
	if file_idx == -1 {
		file_idx = i16(table.filelist.len)
		table.filelist << path
	}
	mut p := Parser{
		content: .file
		scanner: scanner.new_scanner_file(path, file_idx, comments_mode, pref_) or { panic(err) }
		table:   table
		pref:    pref_
		// Only set vls mode if it's the file the user requested via `v -vls-mode file.v`
		// Otherwise we'd be parsing entire stdlib in vls mode
		is_vls:           pref_.is_vls && path == pref_.path
		is_vls_skip_file: should_skip_vls_file(pref_, path)
		scope:            &ast.Scope{
			start_pos: 0
			parent:    table.global_scope
		}
		errors:           []errors.Error{}
		warnings:         []errors.Warning{}
		file_idx:         file_idx
	}
	p.set_path(path)
	res := p.parse()
	unsafe { p.free_scanner() }
	return res
}

pub fn (mut p Parser) parse() &ast.File {
	$if trace_parse ? {
		eprintln('> ${@FILE}:${@LINE} | p.path: ${p.file_path} | content: ${p.content} | nr_tokens: ${p.scanner.all_tokens.len} | nr_lines: ${p.scanner.line_nr} | nr_bytes: ${p.scanner.text.len}')
	}
	util.timing_start('PARSE')
	defer {
		util.timing_measure_cumulative('PARSE')
	}
	// comments_mode: comments_mode
	p.init_parse_fns()
	p.read_first_token()
	mut stmts := []ast.Stmt{}
	for p.tok.kind == .comment {
		stmts << p.comment_stmt()
	}
	// module
	module_decl := p.module_decl()
	if module_decl.is_skipped {
		stmts.insert(0, ast.Stmt(module_decl))
	} else {
		stmts << module_decl
	}
	p.inside_import_section = true
	// imports
	for {
		if p.tok.kind == .key_import {
			stmts << p.import_stmt()
			continue
		}
		if p.tok.kind == .comment {
			stmts << p.comment_stmt()
			continue
		}
		break
	}
	for {
		if p.tok.kind == .eof {
			if !p.is_vls_skip_file {
				p.check_unused_imports()
			}
			break
		}
		stmt := p.top_stmt()
		// clear the attributes after each statement
		if !(stmt is ast.ExprStmt && stmt.expr is ast.Comment) {
			p.attrs = []
		}
		stmts << stmt
		if p.should_abort {
			break
		}
	}
	p.scope.end_pos = p.tok.pos

	mut errors_ := p.errors.clone()
	mut warnings := p.warnings.clone()
	mut notices := p.notices.clone()

	if p.pref.check_only {
		errors_ << p.scanner.errors
		warnings << p.scanner.warnings
		notices << p.scanner.notices
	}

	if p.pref.is_check_overflow {
		p.register_auto_import('builtin.overflow')
	}
	p.handle_codegen_for_file()

	ast_file := &ast.File{
		path:                  p.file_path
		path_base:             p.file_base
		is_generated:          p.is_generated
		is_translated:         p.is_translated
		language:              p.file_backend_mode
		nr_lines:              p.scanner.line_nr
		nr_bytes:              p.scanner.text.len
		nr_tokens:             p.scanner.all_tokens.len
		mod:                   module_decl
		imports:               p.ast_imports
		imported_symbols:      p.imported_symbols
		imported_symbols_trie: token.new_keywords_matcher_from_array_trie(p.imported_symbols.keys())
		imported_symbols_used: p.imported_symbols_used
		auto_imports:          p.auto_imports
		used_imports:          p.used_imports
		implied_imports:       p.implied_imports
		stmts:                 stmts
		scope:                 p.scope
		global_scope:          p.table.global_scope
		errors:                errors_
		warnings:              warnings
		notices:               notices
		global_labels:         p.global_labels
		template_paths:        p.template_paths
		unique_prefix:         p.unique_prefix
	}
	$if trace_parse_file_path_and_mod ? {
		eprintln('>> ast.File, tokens: ${ast_file.nr_tokens:5}, mname: ${ast_file.mod.name:20}, sname: ${ast_file.mod.short_name:11}, path: ${p.file_display_path}')
	}
	return ast_file
}

pub fn parse_files(paths []string, mut table ast.Table, pref_ &pref.Preferences) []&ast.File {
	mut timers := util.new_timers(should_print: false, label: 'parse_files: ${paths}')
	$if time_parsing ? {
		timers.should_print = true
	}
	unsafe {
		mut files := []&ast.File{cap: paths.len}
		for path in paths {
      if pref_.is_verbose {
        println('parse file: ${path}')
      }
			timers.start('parse_file ${path}')
			files << parse_file(path, mut table, .skip_comments, pref_)
			timers.show('parse_file ${path}')
		}
		handle_codegen_for_multiple_files(mut files)
		return files
	}
}

