/* Option A speed lower bound: mutable-tree build (yyjson_doc_mut_copy, C-only, no Swift calls) + yyjson_mut_write. */
#include "yyjson.h"
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
static double now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec*1e3+t.tv_nsec/1e6;}
static int cmp(const void*a,const void*b){double x=*(double*)a,y=*(double*)b;return x<y?-1:x>y;}
int main(int argc,char**argv){
  FILE*f=fopen(argv[1],"rb");fseek(f,0,SEEK_END);long n=ftell(f);fseek(f,0,SEEK_SET);char*b=malloc(n);fread(b,1,n,f);fclose(f);
  yyjson_doc*d=yyjson_read(b,n,0); int it=101; double t[101]; size_t len=0;
  for(int i=0;i<it;i++){double s=now(); yyjson_mut_doc*m=yyjson_doc_mut_copy(d,NULL); char*o=yyjson_mut_write(m,0,&len); free(o); yyjson_mut_doc_free(m); t[i]=now()-s;}
  qsort(t,it,sizeof(double),cmp); printf("option A (C mut copy + write): median %.3f ms, %zu bytes out, %.0f MB/s\n",t[it/2],len,len/t[it/2]/1e3);
  for(int i=0;i<it;i++){double s=now(); yyjson_mut_doc*m=yyjson_doc_mut_copy(d,NULL); t[i]=now()-s; yyjson_mut_doc_free(m);}
  qsort(t,it,sizeof(double),cmp); printf("  of which tree build: median %.3f ms\n",t[it/2]);
}
