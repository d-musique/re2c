%{

/* $Id$ */

#include <time.h>
#include <iostream.h>
#include <string.h>
#include <malloc.h>
#include "globals.h"
#include "parser.h"
#include "version.h"

extern "C"
{
int yyparse();
int yylex();
void yyerror(char*);
}

static uint accept;
static RegExp *spec;
static Scanner *in;

/* Bison version 1.875 emits a definition that is not working
 * with several g++ version. Hence we disable it here.
 */
#if defined(__GNUC__)
#define __attribute__(x)
#endif

%}

%start	spec

%union {
    Symbol	*symbol;
    RegExp	*regexp;
    Token	*token;
    char	op;
}

%token		CLOSE	ID	CODE	RANGE	STRING

%type	<op>		CLOSE
%type	<op>		close
%type	<symbol>	ID
%type	<token>		CODE
%type	<regexp>	RANGE	STRING
%type	<regexp>	rule	look	expr	diff	term	factor	primary

%%

spec	:
		{ accept = 0;
		  spec = NULL; }
	|	spec rule
		{ spec = spec? mkAlt(spec, $2) : $2; }
	|	spec decl
	;

decl	:	ID '=' expr ';'
		{ if($1->re)
		      in->fatal("sym already defined");
		  $1->re = $3; }
	;

rule	:	expr look CODE
		{ $$ = new RuleOp($1, $2, $3, accept++); }
	;

look	:
		{ $$ = new NullOp; }
	|	'/' expr
		{ $$ = $2; }
	;

expr	:	diff
		{ $$ = $1; }
	|	expr '|' diff
		{ $$ =  mkAlt($1, $3); }
	;

diff	:	term
		{ $$ = $1; }
	|	diff '\\' term
		{ $$ =  mkDiff($1, $3);
		  if(!$$)
		       in->fatal("can only difference char sets");
		}
	;

term	:	factor
		{ $$ = $1; }
	|	term factor
		{ $$ = new CatOp($1, $2); }
	;

factor	:	primary
		{ $$ = $1; }
	|	primary close
		{
		    switch($2){
		    case '*':
			$$ = mkAlt(new CloseOp($1), new NullOp());
			break;
		    case '+':
			$$ = new CloseOp($1);
			break;
		    case '?':
			$$ = mkAlt($1, new NullOp());
			break;
		    }
		}
	;

close	:	CLOSE
		{ $$ = $1; }
	|	close CLOSE
		{ $$ = ($1 == $2) ? $1 : '*'; }
	;

primary	:	ID
		{ if(!$1->re)
		      in->fatal("can't find symbol");
		  $$ = $1->re; }
	|	RANGE
		{ $$ = $1; }
	|	STRING
		{ $$ = $1; }
	|	'(' expr ')'
		{ $$ = $2; }
	;

%%

extern "C" {
void yyerror(char* s){
    in->fatal(s);
}

int yylex(){
    return in->scan();
}
} // end extern "C"

void line_source(unsigned int line, ostream& o)
{
    char *	fnamebuf;
    char *	token;

    o << "#line " << line << " \"";
    if( fileName != NULL ) {
    	fnamebuf = strdup( fileName );
    } else {
	fnamebuf = strdup( "<stdin>" );
    }
    token = strtok( fnamebuf, "\\" );
    for(;;) {
	o << token;
	token = strtok( NULL, "\\" );
	if( token == NULL ) break;
	o << "\\\\";
    }
    o << "\"\n";
    ++oline;
    free( fnamebuf );
}

void parse(int i, ostream &o){

    o << "/* Generated by re2c " RE2C_VERSION " on ";
    time_t now = time(&now);
    o.write(ctime(&now), 24);
    o << " */\n";
    oline += 2;

    in = new Scanner(i);

    line_source(in->line(), o);

    while(in->echo(o)){
	yyparse();
	if(spec)
	    genCode(o, spec);
	line_source(in->line(), o);
    }
}
