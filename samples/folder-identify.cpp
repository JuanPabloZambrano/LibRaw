/* -*- C++ -*-
 * File: folder-identify.cpp
 * Copyright 2025 LibRaw LLC (info@libraw.org)
 *
 * LibRaw C++ demo: recursively identify raw files in folder structure
 * and print normalized camera names with DNG status
 *
 * LibRaw is free software; you can redistribute it and/or modify
 * it under the terms of the one of two licenses as you choose:
 *
 * 1. GNU LESSER GENERAL PUBLIC LICENSE version 2.1
 *    (See file LICENSE.LGPL provided in LibRaw distribution archive for details).
 *
 * 2. COMMON DEVELOPMENT AND DISTRIBUTION LICENSE (CDDL) Version 1.0
 *    (See file LICENSE.CDDL provided in LibRaw distribution archive for details).
 */

#include <stdio.h>
#include <string.h>
#include <vector>
#include <algorithm>
#include <string>

#include "libraw/libraw.h"

#ifdef LIBRAW_WIN32_CALLS
#define snprintf _snprintf
#include <windows.h>
#include <direct.h>
#else
#include <sys/stat.h>
#include <dirent.h>
#include <unistd.h>
#endif

#ifndef MAX_PATH
#ifdef PATH_MAX
#define MAX_PATH PATH_MAX
#else
#define MAX_PATH 4096
#endif
#endif

#define P1 MyCoolRawProcessor.imgdata.idata

bool is_dng_file(const char *filename)
{
  const char *dot = strrchr(filename, '.');
  if (!dot)
    return false;
  return !strcasecmp(dot, ".dng");
}

bool should_skip_dir(const char *dirname)
{
  return !strcmp(dirname, ".git") || !strcmp(dirname, ".git-lfs");
}

struct FileInfo
{
  std::string filename;
  std::string filepath;
  std::string make;
  std::string model;
  bool is_dng;
};

void print_usage(const char *pname)
{
  printf("Usage: %s [options] <folder_path>\n", pname);
  printf("Recursively identifies raw files in folder and subfolders.\n");
  printf("Options:\n");
  printf("  -j filename    Export results to JSON file\n");
  printf("  -p             Include file path in JSON output\n");
  printf("Outputs: filename | normalized_make/model | is_dng\n");
}

#ifdef LIBRAW_WIN32_CALLS
void list_files_recursive(const char *path, LibRaw &MyCoolRawProcessor, std::vector<FileInfo> &results)
{
  WIN32_FIND_DATAA ffd;
  HANDLE find_handle;
  char search_path[MAX_PATH];
  char full_path[MAX_PATH];

  snprintf(search_path, MAX_PATH, "%s\\*", path);

  find_handle = FindFirstFileA(search_path, &ffd);
  if (find_handle == INVALID_HANDLE_VALUE)
    return;

  do
  {
    if (!strcmp(ffd.cFileName, ".") || !strcmp(ffd.cFileName, ".."))
      continue;

    snprintf(full_path, MAX_PATH, "%s\\%s", path, ffd.cFileName);

    if (ffd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
    {
      if (!should_skip_dir(ffd.cFileName))
        list_files_recursive(full_path, MyCoolRawProcessor, results);
    }
    else
    {
      int ret = MyCoolRawProcessor.open_file(full_path);
      if (ret == LIBRAW_SUCCESS)
      {
        MyCoolRawProcessor.adjust_sizes_info_only();

        FileInfo info;
        info.filename = ffd.cFileName;
        info.filepath = full_path;
        info.make = P1.normalized_make;
        info.model = P1.normalized_model;
        info.is_dng = is_dng_file(ffd.cFileName);
        results.push_back(info);

        MyCoolRawProcessor.recycle();
      }
    }
  } while (FindNextFileA(find_handle, &ffd));

  FindClose(find_handle);
}
#else
void list_files_recursive(const char *path, LibRaw &MyCoolRawProcessor, std::vector<FileInfo> &results)
{
  DIR *dir;
  struct dirent *entry;
  struct stat file_stat;
  char full_path[MAX_PATH];

  dir = opendir(path);
  if (!dir)
    return;

  while ((entry = readdir(dir)) != NULL)
  {
    if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, ".."))
      continue;

    snprintf(full_path, MAX_PATH, "%s/%s", path, entry->d_name);

    if (stat(full_path, &file_stat) == -1)
      continue;

    if (S_ISDIR(file_stat.st_mode))
    {
      if (!should_skip_dir(entry->d_name))
        list_files_recursive(full_path, MyCoolRawProcessor, results);
    }
    else
    {
      int ret = MyCoolRawProcessor.open_file(full_path);
      if (ret == LIBRAW_SUCCESS)
      {
        MyCoolRawProcessor.adjust_sizes_info_only();

        FileInfo info;
        info.filename = entry->d_name;
        info.filepath = full_path;
        info.make = P1.normalized_make;
        info.model = P1.normalized_model;
        info.is_dng = is_dng_file(entry->d_name);
        results.push_back(info);

        MyCoolRawProcessor.recycle();
      }
    }
  }

  closedir(dir);
}
#endif

void write_json(const char *filename, const std::vector<FileInfo> &results, bool include_path)
{
  FILE *f = fopen(filename, "w");
  if (!f)
  {
    fprintf(stderr, "Cannot open %s for writing\n", filename);
    return;
  }

  fprintf(f, "[\n");
  for (size_t i = 0; i < results.size(); i++)
  {
    fprintf(f, "  {\n");
    fprintf(f, "    \"filename\": \"%s\",\n", results[i].filename.c_str());
    if (include_path)
      fprintf(f, "    \"filepath\": \"%s\",\n", results[i].filepath.c_str());
    fprintf(f, "    \"normalized_make\": \"%s\",\n", results[i].make.c_str());
    fprintf(f, "    \"normalized_model\": \"%s\",\n", results[i].model.c_str());
    fprintf(f, "    \"is_dng\": %s\n", results[i].is_dng ? "true" : "false");
    fprintf(f, "  }%s\n", i < results.size() - 1 ? "," : "");
  }
  fprintf(f, "]\n");

  fclose(f);
}

void print_results(const std::vector<FileInfo> &results)
{
  printf("%-50s | Normalized Camera       | DNG\n", "File Path");
  printf("--------------------------------------------------+---------------------------+-----\n");

  for (size_t i = 0; i < results.size(); i++)
  {
    const char *is_dng = results[i].is_dng ? "YES" : "NO";
    printf("%-50s | %s/%s | %s\n", results[i].filename.c_str(),
           results[i].make.c_str(), results[i].model.c_str(), is_dng);
  }
}

int main(int ac, char *av[])
{
  if (ac < 2)
  {
    print_usage(av[0]);
    return 1;
  }

  const char *folder_path = NULL;
  const char *json_file = NULL;
  bool include_path = false;

  for (int i = 1; i < ac; i++)
  {
    if (!strcmp(av[i], "-j") && i < ac - 1)
    {
      json_file = av[i + 1];
      i++;
    }
    else if (!strcmp(av[i], "-p"))
    {
      include_path = true;
    }
    else
    {
      folder_path = av[i];
    }
  }

  if (!folder_path)
  {
    print_usage(av[0]);
    return 1;
  }

  LibRaw MyCoolRawProcessor;
  struct stat path_stat;
  if (stat(folder_path, &path_stat) != 0 || !S_ISDIR(path_stat.st_mode))
  {
    fprintf(stderr, "Error: '%s' is not a valid directory\n", folder_path);
    return 1;
  }

  std::vector<FileInfo> results;
  list_files_recursive(folder_path, MyCoolRawProcessor, results);

  if (json_file)
  {
    write_json(json_file, results, include_path);
    printf("Results exported to %s\n", json_file);
  }
  else
  {
    print_results(results);
  }

  return 0;
}
