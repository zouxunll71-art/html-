// Disposable preview PNG: preserve every sample and metadata chunk, use unfiltered
// stored DEFLATE blocks to avoid repeating Paeth/inflate work on every route change.
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>
static uint32_t be(const unsigned char*p){return (uint32_t)p[0]<<24|(uint32_t)p[1]<<16|(uint32_t)p[2]<<8|p[3];}
static void put(unsigned char*p,uint32_t n){p[0]=n>>24;p[1]=n>>16;p[2]=n>>8;p[3]=n;}
static int paeth(int a,int b,int c){int p=a+b-c,pa=abs(p-a),pb=abs(p-b),pc=abs(p-c);return pa<=pb&&pa<=pc?a:pb<=pc?b:c;}
int main(int argc,char**argv){
 if(argc!=3)return 2;FILE*f=fopen(argv[1],"rb");if(!f)return 3;fseek(f,0,SEEK_END);long n=ftell(f);rewind(f);if(n<57||n>128*1024*1024)return 4;unsigned char*src=malloc(n);if(!src)return 20;if(fread(src,1,n,f)!=(size_t)n)return 5;fclose(f);
 if(memcmp(src,"\x89PNG\r\n\x1a\n",8)||be(src+8)!=13||memcmp(src+12,"IHDR",4))return 6;
 uint32_t w=be(src+16),h=be(src+20);int channels=src[25]==2?3:src[25]==6?4:0;
 if(!w||!h||w>32768||h>32768||(uint64_t)w*h>16000000||!channels||src[24]!=8||src[26]||src[27]||src[28])return 7;
 size_t idsize=0;int ended=0,closed=0;for(size_t p=8;p<(size_t)n;){if(p+12>(size_t)n)return 8;uint32_t len=be(src+p);if((uint64_t)p+12+len>(size_t)n)return 8;
  unsigned char*t=src+p+4;if(p!=8&&!memcmp(t,"IHDR",4))return 6;if(crc32(0,t,len+4)!=be(src+p+8+len))return 9;
  if(!memcmp(t,"acTL",4)||!memcmp(t,"eXIf",4))return 10;
  if(!memcmp(t,"IDAT",4)){if(closed)return 11;idsize+=len;}else if(idsize)closed=1;
  if(!memcmp(t,"IEND",4)){if(len||p+12!=(size_t)n)return 12;ended=1;}
  if(!(t[0]&32)&&memcmp(t,"IHDR",4)&&memcmp(t,"PLTE",4)&&memcmp(t,"IDAT",4)&&memcmp(t,"IEND",4))return 13;p+=len+12;
 }if(!ended||!idsize)return 14;
 unsigned char*idat=malloc(idsize);if(!idat)return 20;size_t cursor=0;for(size_t p=8;p<(size_t)n;){uint32_t len=be(src+p);if(!memcmp(src+p+4,"IDAT",4)){memcpy(idat+cursor,src+p+8,len);cursor+=len;}p+=len+12;}
 size_t row=(size_t)w*channels,total=(row+1)*h;unsigned char*raw=malloc(total);if(!raw)return 20;uLongf size=total;if(uncompress(raw,&size,idat,idsize)!=Z_OK||size!=total)return 15;free(idat);
 for(uint32_t y=0;y<h;y++){unsigned char*data=raw+y*(row+1);int filter=*data;*data++=0;unsigned char*prev=y?data-row-1:NULL;if(filter>4)return 16;
  for(size_t x=0;x<row;x++){int a=x>=(size_t)channels?data[x-channels]:0,b=prev?prev[x]:0,c=prev&&x>=(size_t)channels?prev[x-channels]:0;
   data[x]+=(unsigned char)(filter==1?a:filter==2?b:filter==3?(a+b)/2:filter==4?paeth(a,b,c):0);
  }
 }
 uLongf outsize=compressBound(total);unsigned char*out=malloc(outsize);if(!out)return 20;if(compress2(out,&outsize,raw,total,0)!=Z_OK)return 17;free(raw);
 FILE*g=fopen(argv[2],"wb");if(!g)return 18;int wrote=0;fwrite(src,1,8,g);for(size_t p=8;p<(size_t)n;){uint32_t len=be(src+p);if(!memcmp(src+p+4,"IDAT",4)){if(!wrote){unsigned char head[8],crc[4];put(head,outsize);memcpy(head+4,"IDAT",4);uint32_t sum=crc32(0,head+4,4);sum=crc32(sum,out,outsize);put(crc,sum);fwrite(head,1,8,g);fwrite(out,1,outsize,g);fwrite(crc,1,4,g);wrote=1;}}else fwrite(src+p,1,len+12,g);p+=len+12;}
 int failed=ferror(g);if(fclose(g))failed=1;free(src);free(out);return failed?19:0;
}
