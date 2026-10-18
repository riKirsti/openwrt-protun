#include <dlfcn.h>
#include <stdio.h>

int main(int argc, char **argv)
{
    if (argc != 2) {
        fprintf(stderr, "Usage: %s /path/to/libprotun.so\n", argv[0]);
        return 2;
    }

    void *library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (library == NULL) {
        fprintf(stderr, "Unable to load %s: %s\n", argv[1], dlerror());
        return 1;
    }
    if (dlclose(library) != 0) {
        fprintf(stderr, "Unable to close %s: %s\n", argv[1], dlerror());
        return 1;
    }
    printf("Successfully loaded %s\n", argv[1]);
    return 0;
}
