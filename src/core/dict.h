/*****************************************************************
 * Arturo :VM
 * 
 * Programming Language + Compiler
 * (c) 2019-2020 Yanis Zafirópulos (aka Dr.Kameleon)
 *
 * @file: src/core/dict.h
 *****************************************************************/

#ifndef __DICT_H__
#define __DICT_H__

#include "../arturo.h"

/**************************************
  Type definitions
 **************************************/

typedef String* StringP;

typedef Array(Value) ValueArray;
typedef Array(StringP) StringPArray;

typedef struct { 
	int size;
	StringPArray* keys;
	ValueArray* table;
} Dict;

typedef Dict* DictP;
typedef Array(DictP) DictPArray;

/**************************************
  Inline Methods
 **************************************/

//-------------------------
// Constructor
//-------------------------

static INLINED Dict* dNew(int cap) {
    Dict* ret = malloc(sizeof(Dict));
    ret->size = 0;
    ret->keys = aNew(StringP,0);
    ret->table = aNew(Value,cap);
    return ret;
}

static INLINED void dAdd(Dict* dest, String* key, Value v) {
	dest->size++;
	Hash32 ind;
	hash32String(key,ind);
	ind %= dest->table->cap;

	aAdd(dest->keys, key);
	dest->table->data[ind] = v;
}

static INLINED Value dGet(Dict* dest, String* key) {
	Hash32 ind;
	hash32String(key,ind);
	ind %= dest->table->cap;
	return dest->table->data[ind];
}

static INLINED void dSet(Dict* dest, String* key, Value v) {
	Hash32 ind;
	hash32String(key,ind);
	ind %= dest->table->cap;
	dest->table->data[ind] = v;
}

static INLINED bool dHasKey(Dict* dest, String* key) {
	aEach(dest->keys,i){
		if (!sCmp(dest->keys->data[i], key)) return true;
	}
	return false;
}

/**************************************
  Macros
 **************************************/

 #define dSize(DEST) \
    DEST->size

 #define dFree(DEST) \
    aFree(DEST->keys); \
    aFree(DEST->table);	\
    free(DEST);

#endif