module c

import v.ast

pub fn (mut g Gen) gen_c_main() {
	if !g.has_main {
		return
	}
	g.out.writeln('')
	g.gen_c_main_header()
	g.writeln('\tmain__main();')
	g.gen_c_main_footer()
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

fn (mut g Gen) gen_c_main_footer() {
	if !g.pref.no_builtin {
		g.writeln('\t_vcleanup();')
	}
	g.writeln2('\treturn 0;', '}')
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
