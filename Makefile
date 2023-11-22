CC = gcc
OUT = -o parser
LE = lex

parser:lex.yy.c y.tab.c y.tab.h
	$(CC) -w -g y.tab.c lex.yy.c -ll -ly $(OUT)

y.tab.c:$(fname).y
	yacc -d -v -t $(fname).y -Wcounterexamples

lex.yy.c:$(fname).l
	$(LE) $(fname).l

clean:
	rm -f lex.yy.c y.tab.c y.tab.h *.output *.o *.out *.exe parser
