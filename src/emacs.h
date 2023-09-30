#ifndef _EMACS
#define _EMACS

#ifdef EMACS_EXPORT
   #define CLASS_DECLSPEC __declspec(dllexport)
#else
   #define CLASS_DECLSPEC __declspec(dllimport)
#endif

CLASS_DECLSPEC int main_func(void);

#endif
