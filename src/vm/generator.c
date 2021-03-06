/*****************************************************************
 * Arturo :VM
 * 
 * Programming Language + Compiler
 * (c) 2019-2020 Yanis Zafirópulos (aka Dr.Kameleon)
 *
 * @file: src/vm/generator.c
 *****************************************************************/

#include "arturo.h"

/**************************************
  Basic Helpers
 **************************************/

void emitOp(OPCODE op) {
	lastOp = op;
	writeByte(BCode, op);
}

void reemitOp(int pos, OPCODE op) {
	rewriteByte(BCode, pos, op);
}

void emitOpByte(OPCODE op, Byte b) {
	lastOp = op;
	writeByte(BCode, op);
	writeByte(BCode, b);
}

void emitOpWord(OPCODE op, Word w) {
	lastOp = op;
	writeByte(BCode, op);
	writeWord(BCode, w);
}

void emitOpDword(OPCODE op, Dword d) {
	lastOp = op;
	writeByte(BCode, op);
	writeDword(BCode, d);
}

void reemitDword(int pos, Dword d) {
	rewriteDword(BCode, pos, d);
}

void emitOpValue(OPCODE op, Value v) {
	lastOp = op;
	writeByte(BCode, op);
	writeValue(BCode, v);
}

/**************************************
  Pushes
 **************************************/

void doPushInt(Value v) {
	if (Kind(v)==IV && I(v)<=10) {
		emitOp((OPCODE)(IPUSH0 + I(v)));
	}
	else {
		processConst(v);
	}
}

/**************************************
  Data storage
 **************************************/

int storeValueData(Value v) {
	int ind;
	//printf("Storing value: %llu of type %s\n",v,getValueTypeStr(v));
	if (Kind(v)<GV) {
		aFind(BData, v, ind);
		if (ind!=-1) { return ind; }
		else {
			aAdd(BData, v);
			return BData->size-1;
		}
	}
	else if (Kind(v)==SV) {
		aEach(BData,i) {
			if ((Kind(BData->data[i])==SV) && 
				(!strcmp(S(BData->data[i])->content, S(v)->content))) { S(v)->refc++; return i; }
		}
		aAdd(BData, v);
		S(v)->refc++;
		return BData->size-1;
	}
	else if (Kind(v)==FV) {
		aEach(BData,i) {
			if (Kind(BData->data[i])==FV) {
				if (F(BData->data[i])->ip==F(v)->ip) { return i; }

				unsigned int memsize = F(v)->to-F(v)->ip;
				if (!memcmp(BCode->data+F(BData->data[i])->ip, BCode->data+F(v)->ip, memsize)) {
					BCode->size = F(v)->ip-5;
					return i;
				}
			}
		}
		aAdd(BData,v);
		return BData->size-1;
	}
	return -1;
}

void processConst(Value v) {
	int ind = storeValueData(v);

	if (ind<=14) { emitOp((OPCODE)(CPUSH0 + ind)); }
	else 		 { emitOpWord(CPUSH, ind); }
}

/**************************************
  Loads, Stores & Calls
 **************************************/

void processCall(char* id) {
	if (weAreInBlock) {
		int ind;
		aFindCStr(LocalLookup, id, ind);
		if (ind!=-1) {
			if (ind<=4)  { emitOp((OPCODE)(LCALL0 + ind)); }
			else 		 { emitOpByte(LCALL, ind); }
		}
		else {
			aFindCStr(GlobalLookup,id,ind);
			if (ind!=-1) {
				//printf("-- found in global scope\n");
				if (ind<=8)  { emitOp((OPCODE)(GCALL0 + ind)); }
				else 		 { emitOpWord(GCALL, ind); }
			}
			else {
				// pretend it exists in global
				aAdd(GlobalLookup,id);
				ind = GlobalLookup->size-1;
				if (ind<=8)  { emitOp((OPCODE)(GCALL0 + ind)); }
				else 		 { emitOpWord(GCALL, ind); }
			}
		}
	}
	else {
		int ind;
		aFindCStr(GlobalLookup, id, ind);
		if (ind!=-1) {
			if (ind<=8)  { emitOp((OPCODE)(GCALL0 + ind)); }
			else 		 { emitOpWord(GCALL, ind); }
		}
		else {
			printf("!! Symbol not found: %s\n",id);
			exit(1);
		}
	}
}

void processLoad(char* id) {
	printf("processLoad: %s\n",id);
	if (weAreInBlock) {
		int ind;
		aFindCStr(LocalLookup, id, ind);
		if (ind!=-1) {
			if (ind<=4)  { emitOp((OPCODE)(LLOAD0 + ind)); }
			else 		 { emitOpByte(LLOAD, ind); }
			printf("\temit as local: %d\n",ind);
		}
		else {
			aFindCStr(GlobalLookup,id,ind);
			if (ind!=-1) {
				//printf("-- found in global scope\n");
				if (ind<=8)  { emitOp((OPCODE)(GLOAD0 + ind)); }
				else 		 { emitOpWord(GLOAD, ind); }
				printf("\temit as global: %d\n",ind);
			}
			else {
				printf("Symbol not found: %s\n",id);
				exit(1);
			}
		}
	}
	else {
		int ind;
		aFindCStr(GlobalLookup, id, ind);
		if (ind!=-1) {
			if (ind<=8)  { emitOp((OPCODE)(GLOAD0 + ind)); }
			else 		 { emitOpWord(GLOAD, ind); }
			printf("\temit as global: %d\n",ind);
		}
		else {
			printf("!! Symbol not found: %s\n",id);
			exit(1);
		}
	}
}

void processStore(char* id) {
	printf("processStore: %s\n",id);
	if (weAreInBlock) {
		//printf("-- we are in a block\n");
		if (dictsFound>0) {
			int ind = storeValueData(strToStringValue(id));
			emitOpWord(DSTORE, ind);
		}
		else {
			int ind;
			aFindCStr(LocalLookup,id,ind);
			if (ind!=-1) {
				//printf("-- found in local scope\n");
				if (ind<=4)  { emitOp((OPCODE)(LSTORE0 + ind)); }
				else   		 { emitOpByte(LSTORE, ind); }
				printf("\temit as local: %d\n",ind);
			}
			else {
				//printf("-- NOT found in local scope\n");
				aFindCStr(GlobalLookup,id,ind);
				if (ind!=-1) {
					//printf("-- found in global scope\n");
					if (ind<=8)  { emitOp((OPCODE)(GSTORE0 + ind)); }
					else 		 { emitOpWord(GSTORE, ind); }
					printf("\temit as global: %d\n",ind);
				}
				else {
					//printf("-- NOT found anywhere, adding to local scope\n");
					aAdd(LocalLookup,id);
					ind = LocalLookup->size-1;
					if (ind<=4)  { emitOp((OPCODE)(LSTORE0 + ind)); }
					else   		 { emitOpByte(LSTORE, ind); }
					printf("\temit as local: %d\n",ind);
				}
			}
		}
	}
	else {
		//printf("-- we are NOT in a block\n");
		if (dictsFound>0) {
			int ind = storeValueData(strToStringValue(id));
			emitOpWord(DSTORE, ind);
		}
		else {
			int ind;
			aFindCStr(GlobalLookup,id,ind);
			if (ind!=-1) {
				//printf("-- found in global scope\n");
				if (ind<=8)  { emitOp((OPCODE)(GSTORE0 + ind)); }
				else 		 { emitOpWord(GSTORE, ind); }
			}
			else {
				//printf("-- NOT found in global scope, add it\n");
				aAdd(GlobalLookup,id);
				ind = GlobalLookup->size-1;
				if (ind<=8)  { emitOp((OPCODE)(GSTORE0 + ind)); }
				else 		 { emitOpWord(GSTORE, ind); }
			}
		}
	}
}

void processInPlace(OPCODE op, char* id) {
	if (weAreInBlock) {
		int ind;
		aFindCStr(LocalLookup, id, ind);
		if (ind!=-1) {
			emitOpWord(op, (Word)ind);
		}
		else {
			aFindCStr(GlobalLookup,id,ind);
			if (ind!=-1) {
				emitOpWord(op, (GLOBAL_VAR|(Word)ind));
			}
			else {
				printf("Symbol not found: %s\n",id);
				exit(1);
			}
		}
	}
	else {
		int ind;
		aFindCStr(GlobalLookup, id, ind);
		if (ind!=-1) {
			emitOpWord(op, (GLOBAL_VAR|(Word)ind));
		}
		else {
			printf("!! Symbol not found: %s\n",id);
			exit(1);
		}
	}
}
/*
void processInPlace(OPCODE op, char* id) {
	if (weAreInBlock) {

	}
	else {
		if (weAreInDict) {

		}
		else {
			int ind;
			aFindCStr(GlobalLookup,id,ind);
			if (ind!=-1) {
				emitOpWord(op, (0x8000|(Word)ind));
			}
			else {
				aAdd(GlobalLookup,id);
				ind = GlobalLookup->size-1;
				emitOpWord(op, (0x8000|(Word)ind));
			}
		}
	}
}*/



/**************************************
  Arrays
 **************************************/

void signalGotInArray() {
	emitOp(NEWARR);
}

void signalFoundArray() {
	emitOp(PUSHA);
}

/**************************************
  Dictionaries
 **************************************/

void signalGotInDictionary() {
	dictsFound++;
	emitOp(NEWDIC);
}

void signalFoundDictionary() {
	dictsFound--;
	emitOp(PUSHD);
}

/**************************************
  Blocks
 **************************************/

void signalFoundIf() {
	inIf = true;
	ifsFound+=2;
	weAreInLoop = false;
	weAreInIf = true;
}

void finalizeIf() {
	unsigned int target = aPop(IfStarts);
	Dword addr = readDword(BCode->data, target+1);
	reemitOp(target, JMPIFNOT);
	if (BCode->data[addr]==JUMP) {
		reemitDword(target+1, addr+5);
	}
	weAreInIf = false;
}

void signalFoundLoop() {
	inLoop += 1;
	weAreInLoop = true;
	weAreInIf = false;
	aAdd(LoopHeaders,BCode->size);
}

void finalizeLoop() {
	weAreInLoop = (--inLoop);
	unsigned int target = aPop(LoopStarts);
	Dword addr = readDword(BCode->data, target+1);
	reemitOp(target, JMPIFNOT);
	emitOpDword(JUMP, aPop(LoopHeaders));
	if (BCode->data[addr]==JUMP) {
		reemitDword(target+1, addr+5);
	}
}

void signalGotInBlock() {
	if (inIf) {
		aAdd(IfStarts,BCode->size);
	}
	if (weAreInLoop) {
		aAdd(LoopStarts,BCode->size);
	}
	aAdd(BlockStarts, BCode->size);
	emitOpDword(JUMP,0);
}

void signalGotOutOfBlock() {
	inIf = false;
	int pos = aPop(BlockStarts)+1; 				// move pointer to Dword after JUMP (1 byte)
	reemitDword(pos,BCode->size);				// fix JMP param to point to current pointer
}

void signalGotInFunction() {
	printf("signalGotInFunction\n");
	if (LocalLookupStack->size > 0) {
		aAdd(LocalLookupStack, LocalLookup->size);
	}
	else {
		aAdd(LocalLookupStack,0);
	}
	weAreInBlock = true;
	aAdd(argCounters,0);
}

void signalFoundFunction() {
	LocalLookup->size = aPop(LocalLookupStack);
	if (LocalLookupStack->size==0) {
		weAreInBlock = false;
	}
	emitOp(RET);
	unsigned int pos = BlockStarts->data[BlockStarts->size] + 1;
	reemitDword(pos,BCode->size);
	Func* f = fNew(pos+4,BCode->size-1,aPop(argCounters));
	//printf("created new func: %p :: ip: %d, args: %d\n",f,f->ip,f->args);
	processConst(toF(f));
}

/**************************************
  Initialization & Finalization
 **************************************/

inline void generatorSetup() {
	BCode 			= aNew(Byte, INITIAL_BCODE_SIZE);
	BData 			= aNew(Value, INITIAL_BDATA_SIZE);

	GlobalLookup 		= aNew(CString, 0);
	LocalLookup 		= aNew(CString, 0);
	LocalLookupStack	= aNew(int, 0);

	BlockStarts 	= aNew(int,0);
	IfStarts 		= aNew(int,0);
	LoopStarts 		= aNew(int,0);
	LoopHeaders 	= aNew(int,0);

	weAreInIf 		= false;
	weAreInLoop		= false;

	ifsFound 		= 0;
	inIf 			= false;
	inLoop			= 0;

	dictsFound 		= 0;

	argCounters 	= aNew(int,0);

	weAreInBlock 	= false;
	weAreInDict 	= false;
}

inline void generatorFinalize() {
	aFree(GlobalLookup);
	aFree(LocalLookupStack);
	aFree(LocalLookup);

	aFree(BlockStarts);
	aFree(IfStarts);
	aFree(LoopStarts);
	aFree(LoopHeaders);

	aFree(argCounters);
}

inline bool generateBytecode(FILE* script) {
	generatorSetup();
	
	yyin = script;
	bool result = !yyparse();

	if (Env.optimize) {
		optimizeBytecode();
	}

	generatorFinalize();

	return result;
}