#ifndef CMARK_GFM_EXPORT_H
#define CMARK_GFM_EXPORT_H

/* Static build: visibility is default (no import/export decoration needed) */
#ifdef CMARK_STATIC_DEFINE
  #define CMARK_GFM_EXPORT
  #define CMARK_GFM_NO_EXPORT
#else
  #if defined(_WIN32) || defined(__CYGWIN__)
    #ifdef cmark_gfm_EXPORTS
      #define CMARK_GFM_EXPORT __declspec(dllexport)
    #else
      #define CMARK_GFM_EXPORT __declspec(dllimport)
    #endif
    #define CMARK_GFM_NO_EXPORT
  #else
    #define CMARK_GFM_EXPORT   __attribute__((visibility("default")))
    #define CMARK_GFM_NO_EXPORT __attribute__((visibility("hidden")))
  #endif
#endif

#endif
