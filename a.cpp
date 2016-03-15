#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <memory>
#include <string>

#define MAX_ATOM_DEPTH 16

typedef struct{
	uint32_t length;
	uint32_t type;
	long size;
}mp4_atom;

typedef struct{
	FILE *fp;

	int depth;
	mp4_atom subs[MAX_ATOM_DEPTH];
	mp4_atom *atom;
	mp4_atom nalu;
}mp4_reader;

void mp4_reader_free(mp4_reader *mp4){
	if(mp4->fp){
		fclose(mp4->fp);
	}
	free(mp4);
}

mp4_reader* mp4_reader_open(const char *filename){
	FILE* fp = fopen(filename, "r");
	if(!fp) {
		return NULL;
	}
	fseek(fp, 0, SEEK_END);
	long filesize = ftell(fp);               // moov atom
	fseek(fp, 0, SEEK_SET);

	mp4_reader *ret = (mp4_reader *)malloc(sizeof(mp4_reader));
	memset(&ret->nalu, 0, sizeof(ret->nalu));
	memset(&ret->subs, 0, sizeof(ret->subs));
	ret->fp = fp;
	ret->depth = 1;
	ret->subs[0].size = filesize; // subs[0] is file
	ret->atom = &ret->subs[1];    // subs[1] is current
	ret->atom->length = 0;
	return ret;
}

// return 0 or 1
int mp4_reader_next_atom(mp4_reader *mp4){
	mp4_atom *atom = mp4->atom;
	mp4_atom *parent = &mp4->subs[mp4->depth - 1];
	if(atom->size > 0){
		fseek(mp4->fp, atom->size, SEEK_CUR);
	}
	//printf("%d\n", __LINE__);
	parent->size -= atom->length;
	if(parent->size <= 0){
		return 0;
	}

	uint32_t length, type;
	int len;
	len = fread(&length, 4, 1, mp4->fp);
	if(len <= 0){
		return 0;
	}
	fread(&type, 4, 1, mp4->fp);

	length = __builtin_bswap32(length);
	type = __builtin_bswap32(type);
	
	atom->length = length;
	atom->type = type;
	atom->size = length - 8;

	return 1;
}

int mp4_reader_read_atom_data(mp4_reader *mp4, char *buf, int len){
	mp4_atom *atom = mp4->atom;
	mp4_atom *parent = &mp4->subs[mp4->depth - 1];
	len = (len <= atom->size)? len : atom->size;
	if(len <= 0){
		return 0;
	}
	fread(buf, len, 1, mp4->fp);
	atom->size -= len;
	return len;
}

int mp4_reader_next_nalu(mp4_reader *mp4){
	mp4_atom *atom = mp4->atom;
	if(mp4->nalu.size > 0){
		fseek(mp4->fp, mp4->nalu.size, SEEK_CUR);
	}
	atom->size -= mp4->nalu.length;
	if(atom->size <= 0){
		return 0;
	}
	uint32_t length;
	fread(&length, 4, 1, mp4->fp);
	length = __builtin_bswap32(length);
	//printf("'%02x%02x%02x%02x', size: %ld\n", (char)(length>>24)&255, (char)(length>>16)&255, (char)(length>>8)&255, (char)length&255, length);

	// 根据mp4定义, length 不包括自身的长度在内, 但我们设计的结构休 length 字段是包括的
	mp4->nalu.length = length + 4;
	mp4->nalu.size = length;
	return 1;
}

// return bytes read
int mp4_reader_read_nalu(mp4_reader *mp4, char *buf, int len){
	len = (len <= mp4->nalu.size)? len : mp4->nalu.size;
	if(len <= 0){
		return 0;
	}
	fread(buf, len, 1, mp4->fp);
	mp4->nalu.size -= len;
	return len;
}


//#include <inttypes.h>
void read_mp4(const char *filename);

int main(int argc, char **argv){
	read_mp4("../../Downloads/m.mp4");
	read_mp4("../../Downloads/m1.mp4");
	return 0;
}

// TODO: mp4_reader_begin_sub_atom
// TODO: mp4_reader_end_sub_atom

void read_mp4(const char *filename){
	mp4_reader *mp4 = mp4_reader_open(filename);
	if(mp4){
		while(mp4_reader_next_atom(mp4)){
			uint32_t type = mp4->atom->type;
			long size = mp4->atom->size;
			printf("'%c%c%c%c', size: %ld\n", (char)(type>>24)&255, (char)(type>>16)&255, (char)(type>>8)&255, (char)type&255, size);
			if(type == 'moov'){
			}
			if(type == 'mdat'){
				while(mp4_reader_next_nalu(mp4)){
					printf("    nalu len: %6u, atom: %ld\n", mp4->nalu.length, mp4->atom->size);
				}
			}
		}
		mp4_reader_free(mp4);
	}
	printf("\n");
}

void parse_sps_pps(){
	/*
	while ( p < (&data[0] + len))
	{
		if(*((int*)p) == __builtin_bswap32('avcC'))
		{
			p += 4 ; // skip 'avcC'
			p += 4 ; // skip avcC header
			p += 2; // skip skip length and sps count
			uint16_t sps_size = *((uint16_t*)p);
			sps_size = __builtin_bswap16(sps_size);
			p += 2 ; // move pointer as we have just read sps size
			*(int*)(p-4) = sps_size;

			//m_sps.resize(sps_size+4);
			//m_sps.put(p-4, sps_size+4);
			std::string s((char *)p, sps_size);
			printf("sps(%d): ", (int)sps_size);
			for(int i=0; i<s.size(); i++){
				printf(" %02x", (uint8_t)s[i]);
			}
			printf("\n");

			p += sps_size;
			p ++ ; // skip pps count
			uint16_t pps_size = *((uint16_t*)p);
			p+= 2;
			pps_size = __builtin_bswap16(pps_size);
			*(int*)(p-4) = pps_size;

			//m_pps.resize(pps_size+4);
			//m_pps.put(p-4, pps_size+4);

			printf("found\n");

			break;
		}
		++p;
	}
	*/
}

