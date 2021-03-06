/*****************************************************************
 * Arturo :VM
 * 
 * Programming Language + Compiler
 * (c) 2019-2020 Yanis Zafirópulos (aka Dr.Kameleon)
 *
 * @file: src/core/func.h
 *****************************************************************/

#ifndef __FUNC_H__
#define __FUNC_H__

#include "../arturo.h"

/**************************************
  Type definitions
 **************************************/

typedef struct {
    Dword ip;
    Dword to;
    Byte args;
} Func;

/**************************************
  Inline Methods
 **************************************/

//-------------------------
// Constructor
//-------------------------

static INLINED Func* fNew(Dword ip, Dword to, Byte args) {
    Func* ret = malloc(sizeof(Func));
    ret->ip = ip;
    ret->to = to;
    ret->args = args;
    return ret;
}

//-------------------------
// Destructor
//-------------------------

static INLINED void fFree(Func* dest) {
    free(dest);
}

#endif