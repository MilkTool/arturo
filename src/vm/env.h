/*****************************************************************
 * Arturo :VM
 * 
 * Programming Language + Compiler
 * (c) 2019-2020 Yanis Zafirópulos (aka Dr.Kameleon)
 *
 * @file: src/vm/env.h
 *****************************************************************/

#ifndef __ENV_H__
#define __ENV_H__

#include "../arturo.h"

/**************************************
  Type definitions
 **************************************/

typedef struct {
	char** 			argv;
	unsigned int 	argi;

	bool			littleEndian;

	char*			include;
	unsigned int    stackSize;

	bool			optimize;
	bool 			debugBytecode;
	bool 			generateImage;
} Environment;

/**************************************
  Globals
 **************************************/

Environment Env;

#endif