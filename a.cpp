#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <memory>
#include <string>

#define MAX_ATOM_DEPTH 32

typedef struct{
	FILE *fp;
	long filesize;
	long curr;
	int atom_size;
	int nalu_size;
	int sub_depth;
	int sub_size_list[MAX_ATOM_DEPTH];
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
	ret->fp = fp;
	ret->filesize = filesize;
	ret->curr = 0;
	ret->atom_size = 0;
	ret->nalu_size = 0;
	ret->sub_depth = 0;
	return ret;
}

// return 0 or 1
int mp4_reader_next_atom(mp4_reader *mp4, uint32_t *type){
	uint32_t size;
	if(mp4->atom_size > 0){
		fseek(mp4->fp, mp4->atom_size, SEEK_CUR);
		mp4->atom_size = 0;
	}
	int len;
	len = fread(&size, 4, 1, mp4->fp);
	if(len <= 0){
		return 0;
	}
	size = __builtin_bswap32(size);
	fread(type, 4, 1, mp4->fp);
	*type = __builtin_bswap32(*type);
	//printf("%u '%c%c%c%c'\n", size, (char)(type>>24)&255, (char)(type>>16)&255, (char)(type>>8)&255, (char)type&255);
	mp4->atom_size = size - 8;
	return 1;
}

int mp4_reader_read_atom_data(mp4_reader *mp4, char *buf, int len){
	if(len > mp4->atom_size){
		len = mp4->atom_size;
	}
	if(len <= 0){
		return 0;
	}
	fread(buf, len, 1, mp4->fp);
	mp4->atom_size -= len;
	return len;
}

int mp4_reader_next_nalu(mp4_reader *mp4){
	if(mp4->nalu_size > 0){
		fseek(mp4->fp, mp4->nalu_size, SEEK_CUR);
		mp4->atom_size -= mp4->nalu_size;
	}
	if(mp4->atom_size <= 0){
		return 0;
	}
	uint32_t size;
	fread(&size, 4, 1, mp4->fp);
	size = __builtin_bswap32(size);
	mp4->nalu_size = size;
	mp4->atom_size -= 4;
	return 1;
}

int mp4_reader_read_nalu(mp4_reader *mp4, char *buf, int len){
	if(len > mp4->nalu_size){
		len = mp4->nalu_size;
	}
	if(len <= 0){
		return 0;
	}
	fread(buf, len, 1, mp4->fp);
	mp4->nalu_size -= len;
	mp4->atom_size -= len;
	return len;
}

//#include <inttypes.h>
void read_mp4(const char *filename);

int main(int argc, char **argv){
	read_mp4("params.mp4");
	read_mp4("m1.mp4");
	read_mp4("capture.mp4");
	return 0;
}

// TODO: mp4_reader_begin_sub_atom
// TODO: mp4_reader_end_sub_atom

void read_mp4(const char *filename){
	mp4_reader *mp4 = mp4_reader_open(filename);
	if(mp4){
		uint32_t type;
		while(mp4_reader_next_atom(mp4, &type)){
			printf("'%c%c%c%c', len: %d\n", (char)(type>>24)&255, (char)(type>>16)&255, (char)(type>>8)&255, (char)type&255, mp4->atom_size);
			if(type == 'moov'){
			}
			if(type == 'mdat'){
				while(mp4_reader_next_nalu(mp4)){
					printf("    nalu len: %6d, atom: %d\n", mp4->nalu_size, mp4->atom_size);
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

