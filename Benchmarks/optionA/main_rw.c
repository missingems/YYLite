/* Option A probe: read + build a mutable doc + write, using the API a mapper would need. */
#include "yyjson.h"
int main(int argc, char **argv) {
    yyjson_read_err err;
    yyjson_doc *doc = yyjson_read_opts(argv[1], (size_t)argc * 7, 0, NULL, &err);
    if (!doc) return 1;
    yyjson_val *root = yyjson_doc_get_root(doc);
    yyjson_obj_iter it; yyjson_obj_iter_init(root, &it);
    yyjson_val *k; long n = 0;
    while ((k = yyjson_obj_iter_next(&it))) { yyjson_val *v = yyjson_obj_iter_get_val(k);
        if (yyjson_is_str(v)) n += (long)yyjson_get_len(v); else if (yyjson_is_num(v)) n += (long)yyjson_get_num(v);
        else if (yyjson_is_arr(v)) n += (long)yyjson_arr_size(v); }
    yyjson_doc_free(doc);
    yyjson_mut_doc *m = yyjson_mut_doc_new(NULL);
    yyjson_mut_val *o = yyjson_mut_obj(m); yyjson_mut_doc_set_root(m, o);
    yyjson_mut_obj_add_int(m, o, "i", n); yyjson_mut_obj_add_uint(m, o, "u", (unsigned long)n);
    yyjson_mut_obj_add_real(m, o, "d", 0.1 * argc); yyjson_mut_obj_add_bool(m, o, "b", argc > 1);
    yyjson_mut_obj_add_strncpy(m, o, "s", argv[0], (size_t)argc); yyjson_mut_obj_add_null(m, o, "n");
    yyjson_mut_val *a = yyjson_mut_arr(m); yyjson_mut_arr_add_strcpy(m, a, argv[0]); yyjson_mut_obj_add_val(m, o, "a", a);
    size_t len; yyjson_write_err werr;
    char *out = yyjson_mut_write_opts(m, 0, NULL, &len, &werr);
    yyjson_mut_doc_free(m);
    return out ? (int)len : 2;
}
