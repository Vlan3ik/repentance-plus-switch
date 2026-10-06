#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

static char *stored_path;
static char *stored_data;
static int stored_length;

void L_Free(char *pointer) { free(pointer); }

void L_Mod_SaveData(const char *path, const char *data, int length) {
    if (!path || !data || length < 0) return;
    char *new_path = strdup(path);
    char *new_data = malloc((size_t)length + 1);
    if (!new_path || (!new_data && length != 0)) {
        free(new_path);
        free(new_data);
        return;
    }
    if (length != 0) memcpy(new_data, data, (size_t)length);
    new_data[length] = '\0';
    free(stored_path);
    free(stored_data);
    stored_path = new_path;
    stored_data = new_data;
    stored_length = length;
}

char *L_Mod_LoadData(const char *path, int *length) {
    if (length) *length = 0;
    if (!path || !stored_path || strcmp(path, stored_path) != 0) return NULL;
    char *copy = malloc((size_t)stored_length + 1);
    if (!copy) return NULL;
    if (stored_length != 0) memcpy(copy, stored_data, (size_t)stored_length);
    copy[stored_length] = '\0';
    if (length) *length = stored_length;
    return copy;
}

bool L_Mod_HasData(const char *path) {
    return path && stored_path && strcmp(path, stored_path) == 0;
}

void L_Mod_RemoveData(const char *path) {
    if (!path || !stored_path || strcmp(path, stored_path) != 0) return;
    free(stored_path);
    free(stored_data);
    stored_path = NULL;
    stored_data = NULL;
    stored_length = 0;
}
