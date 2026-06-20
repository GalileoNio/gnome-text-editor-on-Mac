#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

static void parent_dir(char *path) {
  char *slash = strrchr(path, '/');
  if (slash == NULL || slash == path) {
    strcpy(path, "/");
  } else {
    *slash = '\0';
  }
}

static void join_path(char *out, size_t out_size, const char *left, const char *right) {
  snprintf(out, out_size, "%s/%s", left, right);
}

static int executable_exists(const char *prefix) {
  char target[PATH_MAX];

  join_path(target, sizeof target, prefix, "bin/gnome-text-editor");
  return access(target, X_OK) == 0;
}

static void prepend_path_env(const char *brew_prefix) {
  const char *old_path = getenv("PATH");
  char value[PATH_MAX * 2];

  snprintf(value,
           sizeof value,
           "%s/bin:/usr/bin:/bin:/usr/sbin:/sbin:%s",
           brew_prefix,
           old_path != NULL ? old_path : "");
  setenv("PATH", value, 1);
}

static void configure_data_env(const char *prefix, const char *brew_prefix) {
  char schemas[PATH_MAX];
  char xdg_data_dirs[PATH_MAX * 3];
  const char *old_xdg = getenv("XDG_DATA_DIRS");

  join_path(schemas, sizeof schemas, prefix, "share/glib-2.0/schemas");
  setenv("GSETTINGS_SCHEMA_DIR", schemas, 1);

  snprintf(xdg_data_dirs,
           sizeof xdg_data_dirs,
           "%s/share:%s/share:%s",
           prefix,
           brew_prefix,
           old_xdg != NULL ? old_xdg : "/usr/local/share:/usr/share");
  setenv("XDG_DATA_DIRS", xdg_data_dirs, 1);
}

static void write_replaced(FILE *out,
                           const char *line,
                           const char *needle,
                           const char *replacement) {
  const char *cursor = line;
  const char *match;
  size_t needle_len = strlen(needle);

  while ((match = strstr(cursor, needle)) != NULL) {
    fwrite(cursor, 1, (size_t)(match - cursor), out);
    fputs(replacement, out);
    cursor = match + needle_len;
  }

  fputs(cursor, out);
}

static void configure_gdk_pixbuf_env(const char *prefix) {
  char module_root[PATH_MAX];
  char loader_dir[PATH_MAX];
  char template_cache[PATH_MAX];
  char cache_parent[PATH_MAX];
  char cache_dir[PATH_MAX];
  char generated_cache[PATH_MAX];
  const char *home = getenv("HOME");
  FILE *in;
  FILE *out;
  char line[4096];

  join_path(module_root, sizeof module_root, prefix, "lib/gdk-pixbuf-2.0/2.10.0");
  join_path(loader_dir, sizeof loader_dir, module_root, "loaders");
  join_path(template_cache, sizeof template_cache, module_root, "loaders.cache");

  if (access(loader_dir, R_OK) != 0 || access(template_cache, R_OK) != 0) {
    return;
  }

  setenv("GDK_PIXBUF_MODULEDIR", loader_dir, 1);

  if (home != NULL && home[0] != '\0') {
    snprintf(cache_parent, sizeof cache_parent, "%s/Library/Caches", home);
    mkdir(cache_parent, 0755);
    join_path(cache_dir, sizeof cache_dir, cache_parent, "GNOME Text Editor");
    mkdir(cache_dir, 0755);
    join_path(generated_cache, sizeof generated_cache, cache_dir, "gdk-pixbuf-loaders.cache");
  } else {
    snprintf(generated_cache, sizeof generated_cache, "/tmp/gnome-text-editor-gdk-pixbuf-loaders.cache");
  }

  in = fopen(template_cache, "r");
  if (in == NULL) {
    return;
  }

  out = fopen(generated_cache, "w");
  if (out == NULL) {
    fclose(in);
    return;
  }

  while (fgets(line, sizeof line, in) != NULL) {
    write_replaced(out, line, "@GDK_PIXBUF_LOADER_DIR@", loader_dir);
  }

  fclose(out);
  fclose(in);
  setenv("GDK_PIXBUF_MODULE_FILE", generated_cache, 1);
}

static void redirect_logs(void) {
  const char *home = getenv("HOME");
  char log_path[PATH_MAX];
  char log_dir[PATH_MAX];
  int fd;
  time_t now;

  if (home != NULL && home[0] != '\0') {
    snprintf(log_dir, sizeof log_dir, "%s/Library/Logs/GNOME Text Editor", home);
    mkdir(log_dir, 0755);
    join_path(log_path, sizeof log_path, log_dir, "launch.log");
  } else {
    snprintf(log_path, sizeof log_path, "/tmp/gnome-text-editor-launch.log");
  }

  fd = open(log_path, O_WRONLY | O_CREAT | O_APPEND, 0644);
  if (fd == -1) {
    return;
  }

  now = time(NULL);
  dprintf(fd, "\n=== %s", ctime(&now));
  dprintf(fd, "launcher started\n");
  dup2(fd, STDOUT_FILENO);
  dup2(fd, STDERR_FILENO);
  close(fd);
}

int main(int argc, char **argv) {
  char executable_path[PATH_MAX];
  char macos_dir[PATH_MAX];
  char contents_dir[PATH_MAX];
  char app_dir[PATH_MAX];
  char workspace_root[PATH_MAX];
  char packaged_prefix[PATH_MAX];
  char prefix[PATH_MAX];
  char target[PATH_MAX];
  char workdir[PATH_MAX];
  const char *brew_prefix;
  uint32_t size = sizeof executable_path;
  char **child_argv;
  int child_argc = 0;

  if (_NSGetExecutablePath(executable_path, &size) != 0) {
    fprintf(stderr, "Executable path is too long.\n");
    return 1;
  }

  if (realpath(executable_path, macos_dir) == NULL) {
    perror("realpath");
    return 1;
  }

  parent_dir(macos_dir);
  snprintf(contents_dir, sizeof contents_dir, "%s", macos_dir);
  parent_dir(contents_dir);
  snprintf(app_dir, sizeof app_dir, "%s", contents_dir);
  parent_dir(app_dir);

  join_path(packaged_prefix, sizeof packaged_prefix, contents_dir, "Resources/_install");
  if (executable_exists(packaged_prefix)) {
    snprintf(prefix, sizeof prefix, "%s", packaged_prefix);
    snprintf(workdir, sizeof workdir, "%s", app_dir);
  } else {
    snprintf(workspace_root, sizeof workspace_root, "%s", macos_dir);
    for (int i = 0; i < 4; i++) {
      parent_dir(workspace_root);
    }

    join_path(prefix, sizeof prefix, workspace_root, "_install");
    snprintf(workdir, sizeof workdir, "%s", workspace_root);
  }

  if (!executable_exists(prefix)) {
    fprintf(stderr, "Could not find gnome-text-editor under %s\n", prefix);
    return 1;
  }

  brew_prefix = getenv("HOMEBREW_PREFIX");
  if (brew_prefix == NULL || brew_prefix[0] == '\0') {
    brew_prefix = "/opt/homebrew";
  }

  redirect_logs();
  prepend_path_env(brew_prefix);
  configure_data_env(prefix, brew_prefix);
  configure_gdk_pixbuf_env(prefix);
  chdir(workdir);

  join_path(target, sizeof target, prefix, "bin/gnome-text-editor");

  child_argv = calloc((size_t)argc + 1, sizeof *child_argv);
  if (child_argv == NULL) {
    perror("calloc");
    return 1;
  }

  child_argv[child_argc++] = target;
  for (int i = 1; i < argc; i++) {
    if (strncmp(argv[i], "-psn_", 5) == 0) {
      continue;
    }
    child_argv[child_argc++] = argv[i];
  }
  child_argv[child_argc] = NULL;

  execv(target, child_argv);
  fprintf(stderr, "Failed to exec %s: %s\n", target, strerror(errno));
  return 1;
}
