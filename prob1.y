%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
void yyerror(char*);
int eflag = 0;
int yylex();
extern FILE * yyin;

char str[1000];

int t = 0; // three address code
int l = 0; // block label
int o = 0; // switch case out

int curScope = 0;
int siblingScope = 0; // akin to a block number
int offset = 0;
int errIdx = 0;
int sbtIdx = 0;
char curType[100];
int curTypeSize = 0;

// generation functions
char* genLabel();
char* genBlockLabel();
char* genSwitchOutLabel();

// Integer Stack
typedef struct{
	int elements[10000];
	int top;
} IntegerStack;
void initIntegerStack(IntegerStack*);
void push(IntegerStack*, int);
int pop(IntegerStack* stack);
int peek(IntegerStack* stack);

// Character Stack
typedef struct{
	char* elements[10000];
	int top;
} Stack;
void initStack(Stack*);
void pushChar(Stack*, char*);
char* popChar(Stack* stack);
char* peekChar(Stack* stack);

Stack* switchVars; 
Stack* conditionalOuts; 
Stack* nextBlocks;

// details for variables
struct typeDetails{
	char* type;
	int size;
};

struct lexemeDetails{
	char* type;
	char* address;
	char* name;
	int scope;
	int sibScope;
	int width;
	union{
		int intVal;
		float floatVal;
		double doubleVal;
	} val;
};

// Hash Map
typedef struct Node {
  char* key;
  struct lexemeDetails value;
  struct Node* next;
} Node;

typedef struct HashMap {
  Node** buckets;
  int capacity;
  int size;
} HashMap;

int hashFunction(char*, int);
HashMap* createHashMap(int);
void insert(HashMap*, char*, struct lexemeDetails);
struct lexemeDetails get(HashMap*, char*);
int existsInHashMap(HashMap*, char*);

HashMap* HT;
IntegerStack* offsetStack;
char* errorMessages[1000];
struct lexemeDetails sbt[100];

// utility functions
char* intToHex(int);

// logging
void varExists(char* id) {
	char* err = (char*)malloc(sizeof(char)*1000);
	strcpy(err, "Error: redeclaration of ");
	strcat(err, id);
	strcpy(errorMessages[errIdx], err);
	errIdx++;
	printf("\nError: redeclaration of %s", id);
}

void varDoesNotExist(char* id) {
	char* err = (char*)malloc(sizeof(char)*1000);
	strcpy(err, "Error: ");
	strcat(err, id);
	strcat(err, " is undeclared in this scope");
	strcpy(errorMessages[errIdx], err);
	errIdx++;
	printf("\nError: %s is undeclared in this scope", id);
}

void conflictingTypes(char* id) {
	char* err = (char*)malloc(sizeof(char)*1000);
	strcpy(err, "Error: conflicting types for ");
	strcat(err, id);
	strcpy(errorMessages[errIdx], err);
	errIdx++;
	printf("\nError: conflicting types for %s", id);
}

void logErrorMessages(){
	for(int i = 0; i < 100 && strcmp(errorMessages[i], "-1") != 0; i++)
		printf("%s\n", errorMessages[i]);
}

void logSymbolTable(){
	printf("\n\nSymbol Table:\n");
	int logScope = 1;
	for(int i = 0; i < 100 && strcmp(sbt[i].name, "-1") != 0; i++){
		if(sbt[i].sibScope != logScope){
			printf("\n");
			logScope = sbt[i].sibScope;
		}
		printf("%s %s %s", sbt[i].address, sbt[i].name, sbt[i].type);
		if(sbt[i].width > 0) printf(" %d", sbt[i].width);
		printf("\n"); 
	}
}

%}

%start Program

%token IF ELSE WHILE SWITCH BREAK CASE DEFAULT ADD SUB MUL DIV EQ LT LTE GT GTE NOT AND OR PREPOSTADD PREPOSTSUB LPAREN RPAREN LCURL RCURL LBRAK RBRAK COLON SEMICOLON COMMA

%nonassoc LT GT LTE GTE NOT EQ
%nonassoc OR
%nonassoc AND
%left ADD SUB
%left MUL DIV
%right LPAREN LCURL
%right RPAREN RCURL
%nonassoc PREPOSTADD PREPOSTSUB

%union{
	int dval;
	char lexeme[200];
	char addr[200];
	char* lab;
	struct typeDetails* td;
	struct lexemeDetails* lxd;
}	

%type <addr> Program
%type <addr> Block

%token <addr> NUMBER
%token <addr> VAR
%token <addr> INT
%token <addr> FLOAT
%token <addr> CHAR

%type <addr> StatementList
%type <addr> Statement
%type <addr> DeclarationStatement
%type <addr> AssignmentStatement
%type <addr> SwitchStatement
%type <addr> IfStatement
%type <addr> WhileStatement
%type <addr> L

%type <addr> SwitchStmt
%type <addr> BreakStmt
%type <addr> DefaultStmt

%type <addr> PreRelexp
%type <addr> Relexp

%type <addr> Term
%type <addr> Factor
%type <addr> SIGNVal
%type <addr> Val
%type <lxd> Array
%type <dval> multiArr
%type <td> Type
%type <lab> dummyLabels

%%

Program:
	Block Program { }
	| { }
	;
	
Block:
    LCURL {
	curScope++;
	siblingScope++;
	push(offsetStack, offset);
	offset = 0;
     } StatementList RCURL {
     	offset = pop(offsetStack);
	curScope--;
     } 
     ; 

StatementList:
		Statement StatementList { }
		| { }
		;

Statement:
	DeclarationStatement SEMICOLON { }
	| AssignmentStatement SEMICOLON { }
	| Block { }
	| IfStatement { }
	| WhileStatement { }
	| SwitchStatement { }
	| SwitchStmt { }
	| DefaultStmt { }
	| BreakStmt { }
	;

DeclarationStatement:
		    Type L { strcpy(curType, ""); }

AssignmentStatement:
		   VAR EQ AssignmentStatement {
			strcpy($$, $1);
			strcpy(str, $$);
			strcat(str, "=");
			strcat(str, $3);
			printf("\n%s", str);
			struct lexemeDetails ld = get(HT, $1);
			if(existsInHashMap(HT, $1)) {
				if(ld.scope > curScope) varDoesNotExist($1);
				else if(ld.scope == curScope && ld.sibScope != curScope) varDoesNotExist($1);
			}
			else varDoesNotExist($1);
 		}
		| Array EQ AssignmentStatement {
			struct lexemeDetails* lexData = (struct lexemeDetails*)malloc(sizeof(struct lexemeDetails));
			lexData = $1;
			strcpy($$, lexData->name);
			strcpy(str, lexData->name);
			strcat(str, "=");
			strcat(str, $3);
			printf("\n%s", str);  
			struct lexemeDetails ld = get(HT, lexData->name);
			if(existsInHashMap(HT, lexData->name)) {
				if(ld.scope < curScope) varDoesNotExist(lexData->name);
				else if(ld.scope == curScope && ld.sibScope != curScope) varDoesNotExist(lexData->name);
			}
			else varDoesNotExist(lexData->name);
		}
		| Term { strcpy($$, $1); }
        	;

L:
 L COMMA VAR {
		struct lexemeDetails lexData;

        	lexData.name = (char*)malloc(1000*sizeof(char));
                strcpy(lexData.name, $3);

                lexData.type = (char*)malloc(1000*sizeof(char));
                strcpy(lexData.type, curType);

                lexData.scope = curScope;
		lexData.sibScope = siblingScope;

                lexData.address = (char*)malloc(1000*sizeof(char));
                lexData.address = intToHex(offset);
	
                offset += curTypeSize;
		lexData.width = 0;		

                struct lexemeDetails ld = get(HT, $3);
                if(existsInHashMap(HT, $3) && ld.scope == curScope && ld.sibScope == siblingScope) {
                        if(strcmp(lexData.type, ld.type) != 0) conflictingTypes($3);
                        else varExists($3);
                }
                else {
                        insert(HT, $3, lexData);
                        sbt[sbtIdx++] = lexData;
                }
 }
 | VAR {
		struct lexemeDetails lexData;

                lexData.name = (char*)malloc(1000*sizeof(char));
                strcpy(lexData.name, $1);

                lexData.type = (char*)malloc(1000*sizeof(char));
                strcpy(lexData.type, curType);

                lexData.scope = curScope;
		lexData.sibScope = siblingScope;

                lexData.address = (char*)malloc(1000*sizeof(char));
                lexData.address = intToHex(offset);

                offset += curTypeSize;
		lexData.width = 0;		

                struct lexemeDetails ld = get(HT, $1);
                if(existsInHashMap(HT, $1) && ld.scope == curScope && ld.sibScope == siblingScope) {
                        if(strcmp(lexData.type, ld.type) != 0) conflictingTypes($1);
                        else varExists($1);
                }
                else {
                        insert(HT, $1, lexData);
                        sbt[sbtIdx++] = lexData;
                }
 }
 | VAR EQ AssignmentStatement {
		struct lexemeDetails lexData;
		lexData.name = (char*)malloc(1000*sizeof(char));
		strcpy(lexData.name, $1);

		lexData.type = (char*)malloc(1000*sizeof(char));
		strcpy(lexData.type, curType);

		lexData.scope = curScope;
		lexData.sibScope = siblingScope;

		lexData.address = (char*)malloc(1000*sizeof(char));
		lexData.address = intToHex(offset);

		offset += curTypeSize;
		lexData.width = 0;		

		struct lexemeDetails ld = get(HT, $1);
		if(existsInHashMap(HT, $1) && ld.scope == curScope && ld.sibScope == siblingScope) {
			if(strcmp(lexData.type, ld.type) != 0) conflictingTypes($1);
			else varExists($1);
		}
		else {
			insert(HT, $1, lexData);
			sbt[sbtIdx++] = lexData;
		}
			
			strcpy($$, $1);
			strcpy(str, $$);
			strcat(str, "=");
			strcat(str, $3);
			printf("\n%s", str);
 	}
	| L COMMA VAR EQ AssignmentStatement {
		struct lexemeDetails lexData;
		lexData.name = (char*)malloc(1000*sizeof(char));
		strcpy(lexData.name, $3);

		lexData.type = (char*)malloc(1000*sizeof(char));
		strcpy(lexData.type, curType);

		lexData.scope = curScope;
		lexData.sibScope = siblingScope;

		lexData.address = (char*)malloc(1000*sizeof(char));
		lexData.address = intToHex(offset);

		offset += curTypeSize;
		lexData.width = 0;		

		struct lexemeDetails ld = get(HT, $3);
		if(existsInHashMap(HT, $3) && ld.scope == curScope && ld.sibScope == siblingScope) {
			if(strcmp(lexData.type, ld.type) != 0) conflictingTypes($3);
			else varExists($3);
		}
		else {
			insert(HT, $3, lexData);
			sbt[sbtIdx++] = lexData;
		}	
			
			strcpy($$, $3);
			strcpy(str, $$);
			strcat(str, "=");
			strcat(str, $5);
			printf("\n%s", str);

	}
 	| L COMMA Array {
		struct lexemeDetails* lexData = (struct lexemeDetails*)malloc(sizeof(struct lexemeDetails));
		lexData = $3;

		struct lexemeDetails lexd;
		lexd.width = lexData->width*curTypeSize;

        	lexd.name = (char*)malloc(1000*sizeof(char));
                strcpy(lexd.name, lexData->name);

                lexd.type = (char*)malloc(1000*sizeof(char));
		strcpy(str, curType); strcat(str, "array");
                strcpy(lexd.type, lexData->type);

                lexd.scope = curScope;
		lexd.sibScope = siblingScope;

                lexd.address = (char*)malloc(1000*sizeof(char));
                lexd.address = intToHex(offset);

		struct lexemeDetails ld = get(HT, lexData->name);
		if(existsInHashMap(HT, lexData->name) && ld.scope == curScope && ld.sibScope == siblingScope) {
			if(strcmp(lexData->type, ld.type) != 0) conflictingTypes(lexData->name);
			else varExists(lexData->name);
		}
		else {
			insert(HT, lexData->name, lexd);
			sbt[sbtIdx++] = lexd;
			offset += lexd.width;
		}
	}
	| Array {
		struct lexemeDetails* lexData = (struct lexemeDetails*)malloc(sizeof(struct lexemeDetails));
		lexData = $1;

		struct lexemeDetails lexd;
		lexd.width = lexData->width*curTypeSize;

        	lexd.name = (char*)malloc(1000*sizeof(char));
                strcpy(lexd.name, lexData->name);

                lexd.type = (char*)malloc(1000*sizeof(char));
		strcpy(str, curType); strcat(str, "array");
                strcpy(lexd.type, lexData->type);

                lexd.scope = curScope;
		lexd.sibScope = siblingScope;

                lexd.address = (char*)malloc(1000*sizeof(char));
                lexd.address = intToHex(offset);

		struct lexemeDetails ld = get(HT, lexData->name);
		if(existsInHashMap(HT, lexData->name) && ld.scope == curScope && ld.sibScope == siblingScope) {
			if(strcmp(lexData->type, ld.type) != 0) conflictingTypes(lexData->name);
			else varExists(lexData->name);
		}
		else {
			insert(HT, lexData->name, lexd);
			sbt[sbtIdx++] = lexd;
			offset += lexd.width;
		}
	}
	| Array EQ AssignmentStatement {
		struct lexemeDetails* lexData = (struct lexemeDetails*)malloc(sizeof(struct lexemeDetails));
		lexData = $1;

		struct lexemeDetails lexd;
		lexd.width = lexData->width*curTypeSize;

        	lexd.name = (char*)malloc(1000*sizeof(char));
                strcpy(lexd.name, lexData->name);

                lexd.type = (char*)malloc(1000*sizeof(char));
		strcpy(str, curType); strcat(str, "array");
                strcpy(lexd.type, lexData->type);

                lexd.scope = curScope;
		lexd.sibScope = siblingScope;

                lexd.address = (char*)malloc(1000*sizeof(char));
                lexd.address = intToHex(offset);

		struct lexemeDetails ld = get(HT, lexData->name);
		if(existsInHashMap(HT, lexData->name) && ld.scope == curScope && ld.sibScope == siblingScope) {
			if(strcmp(lexData->type, ld.type) != 0) conflictingTypes(lexData->name);
			else varExists(lexData->name);
		}
		else {
			insert(HT, lexData->name, lexd);
			sbt[sbtIdx++] = lexd;
			offset += lexd.width;
		}	
	}
	| L COMMA Array EQ AssignmentStatement{
		struct lexemeDetails* lexData = (struct lexemeDetails*)malloc(sizeof(struct lexemeDetails));
		lexData = $3;

		struct lexemeDetails lexd;
		lexd.width = lexData->width*curTypeSize;

        	lexd.name = (char*)malloc(1000*sizeof(char));
                strcpy(lexd.name, lexData->name);

                lexd.type = (char*)malloc(1000*sizeof(char));
		strcpy(str, curType); strcat(str, "array");
                strcpy(lexd.type, lexData->type);

                lexd.scope = curScope;
		lexd.sibScope = siblingScope;

                lexd.address = (char*)malloc(1000*sizeof(char));
                lexd.address = intToHex(offset);

		struct lexemeDetails ld = get(HT, lexData->name);
		if(existsInHashMap(HT, lexData->name) && ld.scope == curScope && ld.sibScope == siblingScope) {
			if(strcmp(lexData->type, ld.type) != 0) conflictingTypes(lexData->name);
			else varExists(lexData->name);
		}
		else {
			insert(HT, lexData->name, lexd);
			sbt[sbtIdx++] = lexd;
			offset += lexd.width;
		}	
	
	}
	;

IfStatement:
	IF LPAREN PreRelexp RPAREN dummyLabels dummyLabels dummyLabels{
		printf("\nif %s goto %s\ngoto %s", $3, $5, $6);
		printf("\n%s:", $5);
	} Block { 
		printf("\ngoto %s", $7);
		printf("\n%s:", $6); 
	} ElseStmt { printf("\n%s:", $7); }
	;

ElseStmt:
	ELSE Statement { }
	| { }
	;

dummyLabels:
	   { $$ = (char*)malloc(100*sizeof(char)); $$ = genBlockLabel(); }
	;

WhileStatement:
	dummyLabels { printf("\n%s:", $1); } WHILE LPAREN PreRelexp RPAREN dummyLabels dummyLabels {
			pushChar(conditionalOuts, $8);
			printf("\nif %s goto %s\ngoto %s", $5, $7, $8);
			printf("\n%s:", $7);
		} Block { 
			strcpy(str, popChar(conditionalOuts));
			printf("\ngoto %s\n%s:", $1, $8); 
		}
	;

SwitchStatement:
	SWITCH LPAREN Term {
			pushChar(switchVars, $3);
			pushChar(conditionalOuts, genSwitchOutLabel());
			pushChar(nextBlocks, "");
		} RPAREN Block {
	   			if(strcmp(peekChar(nextBlocks), "")) printf("\n%s:", popChar(nextBlocks)); 
				printf("\n%s:", popChar(conditionalOuts)); 
				char* temp = popChar(nextBlocks);
				temp = popChar(switchVars); 
		}

SwitchStmt:
	  CASE Term { 	if(nextBlocks->top == -1) { printf("\nError: case outside a switch statement"); return; } 
			else{
				if(strcmp(peekChar(nextBlocks), "")) printf("\n%s:", popChar(nextBlocks)); 
				pushChar(nextBlocks, genBlockLabel()); 
				printf("\nifFalse %s = %s goto %s", peekChar(switchVars), $2, peekChar(nextBlocks)); 
			}
		} COLON { }
	  ;

DefaultStmt:
	DEFAULT {
		if(nextBlocks->top == -1) { printf("\nError: default outside a switch statement"); return; } 
		printf("\n%s:", popChar(nextBlocks)); 
	} COLON  { }
	;

BreakStmt:
	BREAK SEMICOLON {
		if(conditionalOuts->top == -1) { printf("Error: break not inside a loop"); return; } 
		else printf("\ngoto %s", peekChar(conditionalOuts)); 
	}
	;

PreRelexp:
	 PreRelexp AND Relexp {
                strcpy($$, genLabel());
                strcpy(str, $$);
                strcat(str, "=");
                strcat(str, $1);
                strcat(str, "&&");
                strcat(str, $3);
                printf("\n%s", str);
        }
        |
    	PreRelexp OR Relexp {
                strcpy($$, genLabel());
                strcpy(str, $$);
                strcat(str, "=");
                strcat(str, $1);
                strcat(str, "||");
                strcat(str, $3);
                printf("\n%s", str);
        }
	|
	Relexp { strcpy($$, $1); }
	| Term { strcpy($$, $1); }
	;

Relexp:
      	Term LT Term {
		strcpy($$, genLabel());
		strcpy(str, $$);
		strcat(str, "=");
		strcat(str, $1);
		strcat(str, "<");
		strcat(str, $3);
		printf("\n%s", str);
	}
	|
	Term LTE Term {
                strcpy($$, genLabel());
                strcpy(str, $$);
		strcat(str, "=");
                strcat(str, $1);
                strcat(str, "<=");
                strcat(str, $3);
                printf("\n%s", str);
        }
	|
	Term GT Term {
                strcpy($$, genLabel());
                strcpy(str, $$);
		strcat(str, "=");
                strcat(str, $1);
                strcat(str, ">");
                strcat(str, $3);
                printf("\n%s", str);
        }
        |
        Term GTE Term {
                strcpy($$, genLabel());
                strcpy(str, $$);
		strcat(str, "=");
                strcat(str, $1);
                strcat(str, ">=");
                strcat(str, $3);
                printf("\n%s", str);
        }
	|
	Term EQ EQ Term {
                strcpy($$, genLabel());
                strcpy(str, $$);
		strcat(str, "=");
                strcat(str, $1);
                strcat(str, "==");
                strcat(str, $4);
                printf("\n%s", str);
        }
        |
        Term NOT EQ Term {
                strcpy($$, genLabel());
                strcpy(str, $$);
		strcat(str, "=");
                strcat(str, $1);
                strcat(str, "!=");
                strcat(str, $4);
                printf("\n%s", str);
        }
        |
	NOT LPAREN PreRelexp RPAREN {
                strcpy($$, genLabel());
                strcpy(str, $$);
		strcat(str, "=");
                strcat(str, "!");
         	strcat(str, "(");
                strcat(str, $3);
		strcat(str, ")");
                printf("\n%s", str);
        }
	| { }
	;

Term:
        Term ADD Factor {
		strcpy($$, genLabel());
		strcpy(str, $$);
		strcat(str, "=");
		strcat(str, $1);
		strcat(str, "+");
		strcat(str, $3);
		printf("\n%s", str);
	}
	| Term SUB Factor {
		strcpy($$, genLabel());
		strcpy(str, $$);
		strcat(str, "=");
		strcat(str, $1);
        	strcat(str, "-");
	    	strcat(str, $3);
      		printf("\n%s", str);
	}
        | Factor { strcpy($$, $1); }
        ;

Factor:
        Factor MUL SIGNVal { 
		strcpy($$, genLabel());
		strcpy(str, $$);
		strcat(str, "=");
		strcat(str, $1);
                strcat(str, "*");
                strcat(str, $3);
                printf("\n%s", str);
	}
	| Factor DIV SIGNVal {
		strcpy($$, genLabel());
		strcpy(str, $$);
		strcat(str, "=");
		strcat(str, $1);
                strcat(str, "/");
                strcat(str, $3);
                printf("\n%s", str); 
	}
        | SIGNVal { strcpy($$, $1); }
	;

SIGNVal:
        ADD Val {
		strcpy($$, "+");
		strcat($$, $2); 
	}
	| SUB Val { 
		strcpy($$, "-");
		strcat($$, $2); 
	}
        | Val { strcpy($$, $1); }
        ;

Val:
        VAR { 
		strcpy($$, $1); 
		struct lexemeDetails ld = get(HT, $1);
		if(existsInHashMap(HT, $1)) {
				if(ld.scope > curScope) { varDoesNotExist($1); }
				else if(ld.scope == curScope && ld.sibScope != curScope) varDoesNotExist($1);
		}
		else { varDoesNotExist($1); }
	}
	| Array {
		struct lexemeDetails* lexData = (struct lexemeDetails*)malloc(sizeof(struct lexemeDetails));
		lexData = $1;
		strcpy($$, lexData->name);
		struct lexemeDetails ld = get(HT, lexData->name);
		if(existsInHashMap(HT, lexData->name)) {
			if(ld.scope > curScope) varDoesNotExist(lexData->name);
			else if(ld.scope == curScope && ld.sibScope != curScope) varDoesNotExist(lexData->name);
		}
		else varDoesNotExist(lexData->name);
	}
        | NUMBER { 
		//char* buf = (char*)malloc(sizeof(char)*1000);
		//int temp = $1;
		//sprintf(buf, "%d", temp);
		strcpy($$, $1);
	}
        | PREPOSTADD VAR {
		strcpy($$, $2);
		strcpy(str, $$);
		strcat(str, "="); 
		strcat(str, $2);
		strcat(str, "+1");
		printf("\n%s", str); 
		struct lexemeDetails ld = get(HT, $2);
		if(existsInHashMap(HT, $2)) {
				if(ld.scope > curScope) varDoesNotExist($2);
				else if(ld.scope == curScope && ld.sibScope != curScope) varDoesNotExist($2);
		}
		else varDoesNotExist($2);
	}
	| PREPOSTSUB VAR { 
		strcpy($$, $2);
                strcpy(str, $$);
                strcat(str, "=");
                strcat(str, $2);
		strcat(str, "-1");
                printf("\n%s", str); 
		struct lexemeDetails ld = get(HT, $2);
		if(existsInHashMap(HT, $2)) {
				if(ld.scope > curScope) varDoesNotExist($2);
				else if(ld.scope == curScope && ld.sibScope != curScope) varDoesNotExist($2);
		}
		else varDoesNotExist($2);
	}
        | VAR PREPOSTADD { 
		strcpy($$, $1);
                strcpy(str, $$);
                strcat(str, "=");
                strcat(str, $1);
                strcat(str, "+1");
                printf("\n%s", str);
		struct lexemeDetails ld = get(HT, $1);
		if(existsInHashMap(HT, $1)) {
				if(ld.scope > curScope) varDoesNotExist($1);
				else if(ld.scope == curScope && ld.sibScope != curScope) varDoesNotExist($1);
		}
		else varDoesNotExist($1);
	}
	| VAR PREPOSTSUB { 
		strcpy($$, $1);
                strcpy(str, $$);
                strcat(str, "=");
                strcat(str, $1);
                strcat(str, "-1");
                printf("\n%s", str);
		struct lexemeDetails ld = get(HT, $1);
		if(existsInHashMap(HT, $1)) {
				if(ld.scope > curScope) varDoesNotExist($1);
				else if(ld.scope == curScope && ld.sibScope != curScope) varDoesNotExist($1);
		}
		else varDoesNotExist($1);
	}
        | PREPOSTADD Array {
		struct lexemeDetails* lexData = (struct lexemeDetails*)malloc(sizeof(struct lexemeDetails));
		lexData = $2;

		strcpy($$, lexData->name);
		strcpy(str, $$);
		strcat(str, "="); 
		strcat(str, lexData->name);
		strcat(str, "+1");
		printf("\n%s", str); 
		
		struct lexemeDetails ld = get(HT, lexData->name);
		if(existsInHashMap(HT, lexData->name)) {
			if(ld.scope > curScope) varDoesNotExist(lexData->name);
			else if(ld.scope == curScope && ld.sibScope != curScope) varDoesNotExist(lexData->name);
		}
		else varDoesNotExist(lexData->name);
	}
	| PREPOSTSUB Array { 
		struct lexemeDetails* lexData = (struct lexemeDetails*)malloc(sizeof(struct lexemeDetails));
		lexData = $2;

		strcpy($$, lexData->name);
		strcpy(str, $$);
		strcat(str, "="); 
		strcat(str, lexData->name);
		strcat(str, "+1");
		printf("\n%s", str); 
		
		struct lexemeDetails ld = get(HT, lexData->name);
		if(existsInHashMap(HT, lexData->name)) {
			if(ld.scope > curScope) varDoesNotExist(lexData->name);
			else if(ld.scope == curScope && ld.sibScope != curScope) varDoesNotExist(lexData->name);
		}
		else varDoesNotExist(lexData->name);
	}
        | Array PREPOSTADD { 
		struct lexemeDetails* lexData = (struct lexemeDetails*)malloc(sizeof(struct lexemeDetails));
		lexData = $1;

		strcpy($$, lexData->name);
		strcpy(str, $$);
		strcat(str, "="); 
		strcat(str, lexData->name);
		strcat(str, "+1");
		printf("\n%s", str); 
		
		struct lexemeDetails ld = get(HT, lexData->name);
		if(existsInHashMap(HT, lexData->name)) {
			if(ld.scope > curScope) varDoesNotExist(lexData->name);
			else if(ld.scope == curScope && ld.sibScope != curScope) varDoesNotExist(lexData->name);
		}
		else varDoesNotExist(lexData->name);
	}
	| Array PREPOSTSUB { 
		struct lexemeDetails* lexData = (struct lexemeDetails*)malloc(sizeof(struct lexemeDetails));
		lexData = $1;

		strcpy($$, lexData->name);
		strcpy(str, $$);
		strcat(str, "="); 
		strcat(str, lexData->name);
		strcat(str, "-1");
		printf("\n%s", str); 
		
		struct lexemeDetails ld = get(HT, lexData->name);
		if(existsInHashMap(HT, lexData->name)) {
			if(ld.scope > curScope) varDoesNotExist(lexData->name);
			else if(ld.scope == curScope && ld.sibScope != curScope) varDoesNotExist(lexData->name);
		}
		else varDoesNotExist(lexData->name);
	}
        | LPAREN Term RPAREN { strcpy($$, $2); }
	;

Array:
     VAR LBRAK NUMBER RBRAK multiArr {
		int sizeValue = atoi($3);
		int width = $5*sizeValue; // space allocated for the array
		struct lexemeDetails* lexData = (struct lexemeDetails*)malloc(sizeof(struct lexemeDetails));

		lexData->width = width;

        	lexData->name = (char*)malloc(1000*sizeof(char));
                strcpy(lexData->name, $1);

                lexData->type = (char*)malloc(1000*sizeof(char));
		strcpy(str, curType); strcat(str, "array");
                strcpy(lexData->type, str);

                lexData->scope = curScope;
		lexData->sibScope = siblingScope;

                lexData->address = (char*)malloc(1000*sizeof(char));
                lexData->address = intToHex(offset);
		$$ = (struct lexemeDetails*)malloc(sizeof(struct lexemeDetails));
		$$ = lexData;
     }
     | VAR LBRAK VAR RBRAK multiArr {
	/* Review */
     }
     ;

multiArr:
	LBRAK NUMBER RBRAK multiArr {
		int sizeValue = atoi($2);
		$$ = sizeValue * $4;
	}
	| LBRAK VAR RBRAK multiArr {
		/* Review */	
	}
	| { $$ = 1; }
	;

Type:
    INT { 
		$$ = (struct typeDetails*)malloc(sizeof(struct typeDetails)); 
		$$->type = (char*)malloc(1000*sizeof(char));
		strcpy($$->type, "int");
		strcpy(curType, "int"); curTypeSize = 4; 
		$$->size = 4; 
    }
    | FLOAT { 
		$$ = (struct typeDetails*)malloc(sizeof(struct typeDetails)); 
		$$->type = (char*)malloc(1000*sizeof(char));
		strcpy(curType, "float"); curTypeSize = 4; 
		strcpy($$->type, "float"); $$->size = 4; 
    }
    | CHAR { 
		$$ = (struct typeDetails*)malloc(sizeof(struct typeDetails)); 
		$$->type = (char*)malloc(1000*sizeof(char));
		strcpy(curType, "char"); curTypeSize = 1; 
		strcpy($$->type, "char"); $$->size = 1; 
    }
    ;

%%

void yyerror(char* s){
	// printf("%d", yylex());
        // while(yylex() != SEMICOLON && yylex() != EOF);
        printf("\nSyntax Error\n");
       // yyparse();
}

char* genLabel(){
        char* s = (char*)malloc(sizeof(char)*1000);
        char* label = (char*)malloc(sizeof(char)*1000);
        strcpy(s, "t");
        sprintf(label, "%d", t);
        strcat(s, label);
        t++;
        return s;
}

char* genBlockLabel(){
        char* s = (char*)malloc(sizeof(char)*1000);
        char* label = (char*)malloc(sizeof(char)*1000);
        strcpy(s, "L");
        sprintf(label, "%d", l);
        strcat(s, label);
	l++;
        return s;
}

char* genSwitchOutLabel(){
	char* s = (char*)malloc(sizeof(char)*1000);
        char* label = (char*)malloc(sizeof(char)*1000);
        strcpy(s, "out");
        sprintf(label, "%d", o);
        strcat(s, label);
        o++;
        return s;
}

void initStack(Stack* stack){
        stack->top = -1;
}

void pushChar(Stack* stack, char* ele){
        if(stack->top == 9999){
                printf("\n\nStack is full\n");
                return;
        }
        stack->top++;
        stack->elements[stack->top] = ele;
}

char* popChar(Stack* stack){
        if(stack->top == -1){
                printf("\nSyntax Error\n");
                return;
        }
	char* ele = (char*)malloc(sizeof(char)*1000);
	strcpy(ele, stack->elements[stack->top]);
	stack->top--;
        return ele;
}

char* peekChar(Stack* stack){
         if(stack->top == -1){
                printf("\nSyntax Error\n");
                return;
        }
        return stack->elements[stack->top];
}

void initIntegerStack(IntegerStack* stack){
        stack->top = -1;
}

void push(IntegerStack* stack, int ele){
        if(stack->top == 9999){
                printf("\nStack is full\n");
                return;
        }
        stack->top++;
        stack->elements[stack->top] = ele;
}

int pop(IntegerStack* stack){
        if(stack->top == -1){
                printf("\nStack is empty\n");
                return;
        }
        int ele = stack->elements[stack->top];
        stack->top--;
        return ele;
}

int peek(IntegerStack* stack){
         if(stack->top == -1){
                printf("\nStack is empty\n");
                return;
        }
        return stack->elements[stack->top];
}
    
int hashFunction(char* key, int capacity) {
  int hash = 0;
  int i;
  for (i = 0; key[i] != '\0'; i++) {
    hash = (hash * 31 + key[i]) % capacity;
  }
  return hash;
}

HashMap* createHashMap(int capacity) {
  HashMap* hashMap = (HashMap*)malloc(sizeof(HashMap));
  if (!hashMap) {
    return NULL;
  }

  hashMap->buckets = (Node**)malloc(sizeof(Node*) * capacity);
  if (!hashMap->buckets) {
    free(hashMap);
    return NULL;
  }

  for (int i = 0; i < capacity; i++) {
    hashMap->buckets[i] = NULL;
  }

  hashMap->capacity = capacity;
  hashMap->size = 0;
  return hashMap;
}

void insert(HashMap* hashMap, char* key, struct lexemeDetails value) {
  int index = hashFunction(key, hashMap->capacity);
  Node* newNode = (Node*)malloc(sizeof(Node));
  newNode->key = strdup(key);
  newNode->value = value;
  newNode->next = hashMap->buckets[index];

  hashMap->buckets[index] = newNode;
  hashMap->size++;
}

struct lexemeDetails get(HashMap* hashMap, char* key) {
  int index = hashFunction(key, hashMap->capacity);
  Node* node = (Node*)malloc(sizeof(Node));
  node = hashMap->buckets[index];

  while (node) {
    if (strcmp(node->key, key) == 0) {
      return node->value;
    }
    node = node->next;
  }

  struct lexemeDetails l; l.scope = -1;
  return l;
}

int existsInHashMap(HashMap* hashMap, char* key) {
	struct lexemeDetails ld = get(hashMap, key);
	if(ld.scope == -1) return 0;
	return 1;	
}

char* intToHex(int offset){
	char* buf = (char*)malloc(sizeof(char)*1000);
	char* hex = (char*)malloc(sizeof(char)*1000);
	strcpy(hex, "0x");
	
	sprintf(buf, "%x", offset);
	int bufLen = strlen(buf);
	for(int i = 1; i <= 4 - bufLen; i++) strcat(hex, "0");
	strcat(hex, buf);
	return hex;
}

int main(int argc, char* argv[])
{
        if(argc > 1)
        {
                FILE *fp = fopen(argv[1], "r");
                if(fp) yyin = fp;
        }

	HT = createHashMap(1000);
	offsetStack = (IntegerStack*)malloc(sizeof(IntegerStack));
	initIntegerStack(offsetStack);
	for(int i = 0; i < 100; i++) {
		errorMessages[i] = (char*)malloc(sizeof(char)*1000);
		strcpy(errorMessages[i], "-1");
	}
	for(int i = 0; i < 100; i++){
		struct lexemeDetails temp;
		temp.name = (char*)malloc(sizeof(char)*1000);
		strcpy(temp.name, "-1");
		sbt[i] = temp;
	}
	switchVars = (Stack*)malloc(sizeof(Stack));
	conditionalOuts = (Stack*)malloc(sizeof(Stack));
	nextBlocks = (Stack*)malloc(sizeof(Stack));

	initStack(switchVars);
	initStack(conditionalOuts);
	initStack(nextBlocks);
	
	yyparse();

	/*if(strcmp(errorMessages[0], "-1") != 0) logErrorMessages();
	else logSymbolTable(); */
	logSymbolTable();

        return 0;
}
