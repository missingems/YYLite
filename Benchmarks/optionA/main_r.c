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
    return (int)n;
}
