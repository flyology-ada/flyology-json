/* Copyright (c) 2026 Yurii Rashkovskii */
/* SPDX-License-Identifier: MIT OR Apache-2.0 */

#include <stddef.h>
#include "yyjson.h"

size_t flyology_bench_yyjson_sizeof_document(void) {
    return sizeof(yyjson_doc);
}

size_t flyology_bench_yyjson_sizeof_read_error(void) {
    return sizeof(yyjson_read_err);
}

size_t flyology_bench_yyjson_sizeof_read_code(void) {
    return sizeof(yyjson_read_code);
}

size_t flyology_bench_yyjson_sizeof_write_error(void) {
    return sizeof(yyjson_write_err);
}

size_t flyology_bench_yyjson_sizeof_write_code(void) {
    return sizeof(yyjson_write_code);
}

size_t flyology_bench_yyjson_offsetof_root(void) {
    return offsetof(yyjson_doc, root);
}

size_t flyology_bench_yyjson_offsetof_allocator_context(void) {
    return offsetof(yyjson_doc, alc.ctx);
}

size_t flyology_bench_yyjson_offsetof_data_read(void) {
    return offsetof(yyjson_doc, dat_read);
}

size_t flyology_bench_yyjson_offsetof_values_read(void) {
    return offsetof(yyjson_doc, val_read);
}

size_t flyology_bench_yyjson_offsetof_error_position(void) {
    return offsetof(yyjson_read_err, pos);
}

size_t flyology_bench_yyjson_offsetof_string_pool(void) {
    return offsetof(yyjson_doc, str_pool);
}

size_t flyology_bench_yyjson_offsetof_error_code(void) {
    return offsetof(yyjson_read_err, code);
}

size_t flyology_bench_yyjson_offsetof_error_message(void) {
    return offsetof(yyjson_read_err, msg);
}

size_t flyology_bench_yyjson_offsetof_write_error_code(void) {
    return offsetof(yyjson_write_err, code);
}

size_t flyology_bench_yyjson_offsetof_write_error_message(void) {
    return offsetof(yyjson_write_err, msg);
}
