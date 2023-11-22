%option noyywrap

%{
#include "y.tab.h"
#include <stdio.h>
#include <stdlib.h>
%}

DIGIT [0-9]
ALPHABET [a-zA-Z_]
EQ [=]

%%
"if" { return IF; }
"else" { return ELSE; }
"while" { return WHILE; }
"switch" { return SWITCH; }
"break" { return BREAK; }
"case" { return CASE; }
"default" { return DEFAULT; }
"int" { strcpy(yylval.lexeme, yytext); return INT; }
"float" { strcpy(yylval.lexeme, yytext); return FLOAT; }
"char" { strcpy(yylval.lexeme, yytext); return CHAR; }
{ALPHABET}+({DIGIT}|{ALPHABET})* { strcpy(yylval.lexeme, yytext); return VAR; }
"\+\+" { return PREPOSTADD; }
"\-\-" { return PREPOSTSUB; }
"\+" { return ADD; }
"\-" { return SUB; }
"*" { return MUL; }
"/" { return DIV; }
{EQ} { return EQ; }
"<" { return LT; }
"<=" { return LTE;}
">" { return GT; }
">=" { return GTE; }
"&&" { return AND; }
"||" { return OR; }
"!" { return NOT; }
{DIGIT}+("."{DIGIT}+)? { strcpy(yylval.lexeme, yytext); return NUMBER; }
[ \t\n] ; /* handle whitespaces and new lines */
"\(" { return LPAREN; }
"\)" { return RPAREN; }
"[" { return LBRAK; }
"]" { return RBRAK; }
"{" { return LCURL; }
"}" { return RCURL; }
"," { return COMMA; }
":" { return COLON; }
";" { return SEMICOLON; }
<<EOF>> { return EOF; }
. { return yytext[0]; }
%%`
