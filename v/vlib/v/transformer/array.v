// Copyright (c) 2019-2025 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module transformer

import v.ast

pub fn (mut t Transformer) array_init(mut node ast.ArrayInit) ast.Expr {
	// For JS and Go generate array init using their syntax
	// if t.pref.backend !in [.c, .native] {
	for mut expr in node.exprs {
		expr = t.expr(mut expr)
	}
	if node.has_len {
		node.len_expr = t.expr(mut node.len_expr)
	}
	if node.has_cap {
		node.cap_expr = t.expr(mut node.cap_expr)
	}
	if node.has_init {
		node.init_expr = t.expr(mut node.init_expr)
	}
	return node
}

pub fn (mut t Transformer) find_new_array_len(node ast.AssignStmt) {
	if !t.pref.is_prod {
		return
	}
	// looking for, array := []type{len:int}
	mut right := node.right[0]
	if mut right is ast.ArrayInit {
		mut left := node.left[0]
		if mut left is ast.Ident {
			// we can not analyse mut array
			if left.is_mut {
				t.index.safe_access(left.name, -2)
				return
			}
			// as we do not need to check any value under the setup len
			if !right.has_len {
				t.index.safe_access(left.name, -1)
				return
			}

			mut len := int(0)

			value := right.len_expr
			if value is ast.IntegerLiteral {
				len = value.val.int() + 1
			}

			t.index.safe_access(left.name, len)
		}
	}
}
