#include <erl_nif.h>

static ERL_NIF_TERM add(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    long a, b;
    (void)argc;
    if (!enif_get_long(env, argv[0], &a) || !enif_get_long(env, argv[1], &b)) {
        return enif_make_badarg(env);
    }
    return enif_make_long(env, a + b);
}

static ErlNifFunc funcs[] = {
    {"add", 2, add, 0},
};

ERL_NIF_INIT(Elixir.SampleNif, funcs, NULL, NULL, NULL, NULL)
