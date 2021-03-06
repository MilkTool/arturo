/*****************************************************************
 * Arturo :VM
 * 
 * Programming Language + Compiler
 * (c) 2019-2020 Yanis Zafirópulos (aka Dr.Kameleon)
 *
 * @file: src/lib/system/numbers.h
 *****************************************************************/

#ifndef __LIB_SYSTEM_ARRAYS_H__
#define __LIB_SYSTEM_ARRAYS_H__

/**************************************
  Helpers
 **************************************/

static INLINED int sortCmpI (const void* left, const void* right) {
    int l = I(*((Value*)left));
    int r = I(*((Value*)right));
    if (l > r) return  1;
    if (l < r) return -1;
    return 0;
}

static INLINED int sortCmpS (const void* left, const void* right) {
    String* l = S(*((Value*)left));
    String* r = S(*((Value*)right));

    return sCmp(l,r);
}

/**************************************
  Functions
 **************************************/

#define sys_doMap() {\
	int ip_before = ip;\
	Func* f = F(popS());\
	ValueArray* arr = A(popS());\
	ValueArray* ret = aNew(Value,arr->size);\
	aEach(arr,i) {\
		pushS(arr->data[i]);\
		callFunctionAndReturn(f,doMap);\
		aAdd(ret,popS());\
	}\
	pushS(toA(ret));\
	ip = ip_before;\
}

#define sys_inMap(ARG,G) {\
	int ip_before = ip;\
	Func* f = F(popS());\
	ValueArray* arr = A(ARG);\
	aEach(arr,i) {\
		pushS(arr->data[i]);\
		callFunctionAndReturn(f,inMap##G);\
		arr->data[i]=popS();\
	}\
	ip = ip_before;\
}

#define sys_doFilter() {\
	int ip_before = ip;\
	Func* f = F(popS());\
	ValueArray* arr = A(popS());\
	ValueArray* ret = aNew(Value,arr->size);\
	unsigned int cnt = 0;\
	aEach(arr,i) {\
		pushS(arr->data[i]);\
		callFunctionAndReturn(f,doFilter);\
		if (B(popS())) {\
			ret->data[cnt++] = arr->data[i];\
		}\
	}\
	ret->size = cnt;\
	pushS(toA(ret));\
	ip = ip_before;\
}


#define sys_inFilter(ARG,G) {\
	int ip_before = ip;\
	Func* f = F(popS());\
	ValueArray* arr = A(ARG);\
	unsigned int cnt = 0;\
	aEach(arr,i) {\
		pushS(arr->data[i]);\
		callFunctionAndReturn(f,inFilter##G);\
		if (B(popS())) {\
			arr->data[cnt++] = arr->data[i];\
		}\
	}\
	arr->size = cnt;\
	ip = ip_before;\
}

#define sys_getSlice() {\
	unsigned int to = I(popS());\
	unsigned int from = I(popS());\
	ValueArray* arr = A(popS());\
	ValueArray* ret = aNew(Value,arr->size);\
	for (unsigned int i=from; i<to; i++) {\
		aAdd(ret,arr->data[i]);\
	}\
	pushS(toA(ret));\
}

#define sys_doSort() {\
	Value arg0 = popS();\
	ValueArray* arr = aDup(Value,A(arg0));\
	switch (Kind(arr->data[0])) {\
		case IV: qsort(arr->data,arr->size,arr->typeSize,sortCmpI); break;\
		case SV: qsort(arr->data,arr->size,arr->typeSize,sortCmpS); break;\
		default: printf("cannot sort\n");\
	}\
	pushS(toA(arr));\
}

#define sys_inSort(ARG,G) {\
	ValueArray* arr = A(ARG);\
	switch (Kind(arr->data[0])) {\
		case IV: qsort(arr->data,arr->size,arr->typeSize,sortCmpI); break;\
		case SV: qsort(arr->data,arr->size,arr->typeSize,sortCmpS); break;\
		default: printf("cannot sort\n");\
	}\
}

#define sys_doUnique() {\
	Value arg0 = popS();\
	if (Kind(arg0)!=AV) { printf("not an array\n"); exit(1); }\
	ValueArray* arr = aNew(Value,A(arg0)->size);\
	aEach(A(arg0),i) {\
		if (!vaContains(arr,A(arg0)->data[i])) {\
			aAdd(arr,A(arg0)->data[i]);\
		}\
	}\
	pushS(toA(arr));\
}

#define sys_inSwap(ARG,G) {               	\
	ValueArray* arr = A(ARG);               \
	Value arg1 = popS();                    \
	Value arg0 = popS();                    \
	Value temp = arr->data[I(arg0)];        \
	arr->data[I(arg0)] = arr->data[I(arg1)];\
	arr->data[I(arg1)] = temp;              \
}

#define sys_getProduct() {                \
	Value arg0 = popS();                  \
	Value ret = toI(1);                   \
	ValueArray* arr = A(arg0);            \
	aEach(arr,i) {                        \
		Value old = ret;				  \
		ret = mulValues(ret,arr->data[i]);\
		if (Kind(old)==GV) bFree(G(old)); \
	}                                     \
	pushS(ret);                           \
}

#define sys_getRange() {                                   \
	Value arg1 = popS();                                   \
	Value arg0 = popS();                                   \
	Int32 startVal = I(arg0);                              \
	Int32 stopVal = I(arg1);                               \
	ValueArray* ret = aNew(Value, abs(stopVal-startVal)+1);\
	ret->size = abs(stopVal-startVal)+1;                   \
	Int32 cnt = 0;                                         \
	if (startVal<stopVal) {                                \
		stopVal++;                                         \
		for (Int32 i=startVal; i<stopVal; i++) {           \
			ret->data[cnt++] = toI(i);                     \
		}                                                  \
	}                                                      \
	else {                                                 \
		stopVal--;                                         \
		for (Int32 i=startVal; i>stopVal; i--) {           \
			ret->data[cnt++] = toI(i);                     \
		}                                                  \
	}                                                      \
	pushS(toA(ret));                                       \
}

#endif