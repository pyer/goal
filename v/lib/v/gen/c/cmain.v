module c

import v.util
import v.ast

pub fn (mut g Gen) gen_c_main() {
	if !g.has_main {
		return
	}
	g.out.writeln('')
	main_fn_start_pos := g.out.len

	g.gen_c_main_header()
	g.writeln('\tmain__main();')
	g.gen_c_main_footer()
	if g.pref.printfn_list.len > 0 && 'main' in g.pref.printfn_list {
		println(g.out.after(main_fn_start_pos))
	}
}

fn (mut g Gen) gen_c_main_function_only_header() {
	g.writeln('int main(int ___argc, char** ___argv){')
}

fn (mut g Gen) gen_c_main_function_header() {
	g.gen_c_main_function_only_header()
	g.gen_c_main_trace_calls_hook()
	if !g.pref.no_builtin {
		if _ := g.table.global_scope.find_global('g_main_argc') {
			g.writeln('\tg_main_argc = ___argc;')
		}
		if _ := g.table.global_scope.find_global('g_main_argv') {
			g.writeln('\tg_main_argv = ___argv;')
		}
	}
}

fn (mut g Gen) gen_c_main_header() {
	g.gen_c_main_function_header()
	if !g.pref.no_builtin {
		g.writeln('\t_vinit(___argc, (voidptr)___argv);')
	}
}

pub fn (mut g Gen) gen_c_main_footer() {
	if !g.pref.no_builtin {
		g.writeln('\t_vcleanup();')
	}
	g.writeln2('\treturn 0;', '}')
}

pub fn (mut g Gen) write_tests_definitions() {
	g.includes.writeln('#include <setjmp.h> // write_tests_main')
	g.definitions.writeln('jmp_buf g_jump_buffer;')
}

pub fn (mut g Gen) gen_failing_error_propagation_for_test_fn(or_block ast.OrExpr, cvar_name string) {
	// in test_() functions, an `opt()?` call is sugar for
	// `or { cb_propagate_test_error(@LINE, @FILE, @MOD, @FN, err.msg() ) }`
	// and the test is considered failed
	g.write_defer_stmts_when_needed(or_block.scope, true, or_block.pos)
	paline, pafile, pamod, pafn := g.panic_debug_info(or_block.pos)
	dot_or_ptr := if cvar_name in g.tmp_var_ptr { '->' } else { '.' }
	err_msg := 'IError_name_table[${cvar_name}${dot_or_ptr}err._typ]._method_msg(${cvar_name}${dot_or_ptr}err._object)'
	g.writeln('\tmain__TestRunner_name_table[test_runner._typ]._method_fn_error(test_runner._object, ${paline}, builtin__tos3("${pafile}"), builtin__tos3("${pamod}"), builtin__tos3("${pafn}"), ${err_msg} );')
	g.writeln('\tlongjmp(g_jump_buffer, 1);')
}

pub fn (mut g Gen) gen_failing_return_error_for_test_fn(return_stmt ast.Return, cvar_name string) {
	// in test_() functions, a `return error('something')` is sugar for
	// `or { err := error('something') cb_propagate_test_error(@LINE, @FILE, @MOD, @FN, err.msg() ) return err }`
	// and the test is considered failed
	g.write_defer_stmts_when_needed(return_stmt.scope, true, return_stmt.pos)
	paline, pafile, pamod, pafn := g.panic_debug_info(return_stmt.pos)
	dot_or_ptr := if cvar_name in g.tmp_var_ptr { '->' } else { '.' }
	err_msg := 'IError_name_table[${cvar_name}${dot_or_ptr}err._typ]._method_msg(${cvar_name}${dot_or_ptr}err._object)'
	g.writeln('\tmain__TestRunner_name_table[test_runner._typ]._method_fn_error(test_runner._object, ${paline}, builtin__tos3("${pafile}"), builtin__tos3("${pamod}"), builtin__tos3("${pafn}"), ${err_msg} );')
	g.writeln('\tlongjmp(g_jump_buffer, 1);')
}

pub fn (mut g Gen) gen_c_main_for_tests() {
	main_fn_start_pos := g.out.len
	g.writeln('')
	g.gen_c_main_function_header()
	g.writeln('\tmain__vtest_init();')
	if !g.pref.no_builtin {
		g.writeln('\t_vinit(___argc, (voidptr)___argv);')
	}

	mut all_tfuncs := g.get_all_test_function_names()
	g.writeln('\tstring v_test_file = ${ctoslit(g.pref.path)};')
	if g.pref.show_asserts {
		g.writeln('\tmain__BenchedTests bt = main__start_testing(${all_tfuncs.len}, v_test_file);')
	}
	g.writeln2('', '\tstruct _main__TestRunner_interface_methods _vtrunner = main__TestRunner_name_table[test_runner._typ];')
	g.writeln2('\tvoid * _vtobj = test_runner._object;', '')
	g.writeln('\tmain__VTestFileMetaInfo_free(test_runner.file_test_info);')
	g.writeln('\t*(test_runner.file_test_info) = main__vtest_new_filemetainfo(v_test_file, ${all_tfuncs.len});')
	g.writeln2('\t_vtrunner._method_start(_vtobj, ${all_tfuncs.len});', '')
	for tnumber, tname in all_tfuncs {
		tcname := util.no_dots(tname)
		testfn := unsafe { g.table.fns[tname] }
		lnum := testfn.pos.line_nr + 1
		g.writeln('\tmain__VTestFnMetaInfo_free(test_runner.fn_test_info);')
		g.writeln('\tstring tcname_${tnumber} = _S("${tcname}");')
		g.writeln('\tstring tcmod_${tnumber}  = _S("${testfn.mod}");')
		g.writeln('\tstring tcfile_${tnumber} = ${ctoslit(testfn.file)};')
		g.writeln('\t*(test_runner.fn_test_info) = main__vtest_new_metainfo(tcname_${tnumber}, tcmod_${tnumber}, tcfile_${tnumber}, ${lnum});')
		g.writeln('\t_vtrunner._method_fn_start(_vtobj);')
		g.writeln('\tif (!setjmp(g_jump_buffer)) {')
		//
		if g.pref.show_asserts {
			g.writeln('\t\tmain__BenchedTests_testing_step_start(&bt, tcname_${tnumber});')
		}
		g.writeln('\t\t${tcname}();')
		g.writeln('\t\t_vtrunner._method_fn_pass(_vtobj);')
		//
		g.writeln('\t}else{')
		//
		g.writeln('\t\t_vtrunner._method_fn_fail(_vtobj);')
		//
		g.writeln('\t}')
		if g.pref.show_asserts {
			g.writeln('\tmain__BenchedTests_testing_step_end(&bt);')
		}
		g.writeln('')
	}
	if g.pref.show_asserts {
		g.writeln('\tmain__BenchedTests_end_testing(&bt);')
	}
	g.writeln2('', '\t_vtrunner._method_finish(_vtobj);')
	g.writeln('\tint test_exit_code = _vtrunner._method_exit_code(_vtobj);')

	g.writeln2('\t_vtrunner._method__v_free(_vtobj);', '')
	g.writeln2('\t_vcleanup();', '')
	g.writeln2('\treturn test_exit_code;', '}')
	if g.pref.printfn_list.len > 0 && 'main' in g.pref.printfn_list {
		println(g.out.after(main_fn_start_pos))
	}
}

pub fn (mut g Gen) gen_c_main_trace_calls_hook() {
	if !g.pref.trace_calls {
		return
	}
	should_trace_c_main := g.pref.should_trace_fn_name('C.main')
	g.writeln('\tu8 bottom_of_stack = 0; g_stack_base = &bottom_of_stack; v__trace_calls__on_c_main(${should_trace_c_main});')
}

// gen_dll_main create DllMain() for windows .dll.
pub fn (mut g Gen) gen_dll_main() {
	g.writeln('VV_EXP BOOL DllMain(HINSTANCE hinst,DWORD fdwReason,LPVOID lpvReserved) {
	switch (fdwReason) {
		case DLL_PROCESS_ATTACH : {
#if defined(_VGCBOEHM)
			GC_set_pages_executable(0);
			GC_INIT();
#endif
			_vinit_caller();
			break;
		}
		case DLL_THREAD_ATTACH : {
			break;
		}
		case DLL_THREAD_DETACH : {
			break;
		}
		case DLL_PROCESS_DETACH : {
			_vcleanup_caller();
			break;
		}
		default:
			return false;
	}
	return true;
}
	')
}
