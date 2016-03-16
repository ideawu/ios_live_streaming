#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "mp4_reader.h"

#undef log_debug

#if 0
#define log_debug(fmt, args...)
#define log_atom(a)
#else
#define log_debug(fmt, args...)	do{\
	printf("%s(%3d): " fmt "\n", __FILE__, __LINE__, ##args); \
}while(0);

#define log_atom(a) {\
	log_debug("%*s%c%c%c%c  len: %6d  size: %d", \
		(mp4->depth - 1) * 4, "", \
		(char)(((a)->type>>24)&255), (char)(((a)->type>>16)&255), \
		(char)(((a)->type>>8)&255), (char)(((a)->type)&255), \
		(int)(a)->length, (int)(a)->size); \
}while(0);
#endif

#define MAX_ATOM_DEPTH 32
#define INFINIT_SIZE   -1

static int mp4_reader_input_cb_default(mp4_reader *mp4, void *buf, int size){
	FILE *fp = (FILE *)mp4->user_data;
	if(buf == NULL){
		fseek(fp, size, SEEK_CUR);
	}else{
		size = (int)fread(buf, 1, size, fp);
	}
	return size;
}

mp4_reader* mp4_reader_init(){
	mp4_reader *ret = (mp4_reader *)malloc(sizeof(mp4_reader));
	memset(ret, 0, sizeof(mp4_reader));
	ret->subs = (mp4_atom *)malloc(sizeof(mp4_atom) * MAX_ATOM_DEPTH);
	memset(ret->subs, 0, sizeof(mp4_atom) * MAX_ATOM_DEPTH);
	ret->nalu = (mp4_atom *)malloc(sizeof(mp4_atom));
	memset(ret->nalu, 0, sizeof(mp4_atom));
	
	ret->depth = 1;
	ret->subs[0].size = INFINIT_SIZE;  // subs[0] is file
	ret->atom = &ret->subs[1];         // subs[1] is current
	ret->atom->length = 0;
	ret->user_data = NULL;
	ret->input_cb = NULL;
	return ret;
}

void mp4_reader_free(mp4_reader *mp4){
	if(mp4->input_cb == mp4_reader_input_cb_default && mp4->user_data){
		FILE *fp = (FILE *)mp4->user_data;
		fclose(fp);
	}
	free(mp4->nalu);
	free(mp4->subs);
	free(mp4);
}

mp4_reader* mp4_file_open(const char *filename){
	FILE *fp = fopen(filename, "r");
	if(!fp) {
		return NULL;
	}
	fseek(fp, 0, SEEK_END);
	long filesize = ftell(fp);               // moov atom
	fseek(fp, 0, SEEK_SET);

	mp4_reader *ret = mp4_reader_init();
	ret->subs[0].size = filesize; // subs[0] is file
	ret->user_data = fp;
	ret->input_cb = mp4_reader_input_cb_default;
	return ret;
}

// return 0 or 1
int mp4_reader_next_atom(mp4_reader *mp4){
	mp4_atom *atom = mp4->atom;
	mp4_atom *parent = &mp4->subs[mp4->depth - 1];
	if(atom->size > 0){
		mp4->input_cb(mp4, NULL, (int)atom->size);
	}
	if(parent->size != INFINIT_SIZE){
		parent->size -= atom->length;
		if(parent->size <= 0){
			return 0;
		}
	}

	int len;
	uint32_t length, type;
	len = mp4->input_cb(mp4, &length, 4);
	if(len <= 0){
		return 0;
	}
	len = mp4->input_cb(mp4, &type, 4);
	if(len <= 0){
		return 0;
	}

	length = __builtin_bswap32(length);
	type = __builtin_bswap32(type);
	
	atom->length = length;
	atom->type = type;
	/**
	 if length == 0, this is the last box in file
	 if length == 1,
	 */
	// special atom length
	if(atom->length == 0){
		atom->size = INFINIT_SIZE;
	}else{
		atom->size = length - 8;
	}
	log_atom(atom);

	return 1;
}

int mp4_reader_skip_atom_data(mp4_reader *mp4){
	return mp4_reader_read_atom_data(mp4, NULL, (int)mp4->atom->size);
}

int mp4_reader_read_atom_data(mp4_reader *mp4, void *buf, int size){
	mp4_atom *atom = mp4->atom;
	size = (size <= atom->size)? size : (int)atom->size;
	if(size <= 0){
		return 0;
	}
	int len;
	len = mp4->input_cb(mp4, buf, size);
	if(len <= 0){
		return 0;
	}
	atom->size -= size;
	return size;
}

int mp4_reader_next_nalu(mp4_reader *mp4){
	mp4_atom *atom = mp4->atom;
	if(mp4->nalu->size > 0){
		mp4->input_cb(mp4, NULL, (int)mp4->nalu->size);
	}
	if(atom->size != INFINIT_SIZE){
		atom->size -= mp4->nalu->length;
		if(atom->size <= 0){
			if(atom->size < 0){
				log_debug("it shouldn't be %d(<0)!", (int)atom->size);
			}
			return 0;
		}
	}
	
	int len;
	uint32_t length;
	len = mp4->input_cb(mp4, &length, 4);
	if(len <= 0){
		return 0;
	}
	length = __builtin_bswap32(length);
	//log_debug("%02x %02x %02x %02x", (length>>24)&0xff, (length>>16)&0xff, (length>>8)&0xff, (length>>0)&0xff)

	// 根据mp4定义, length 不包括自身的长度在内, 但我们设计的结构休 length 字段是包括的
	mp4->nalu->length = length + 4;
	mp4->nalu->size = length;
	log_debug("%*snalu len: %6u  size: %5d  atom: %ld",
		(mp4->depth)*4, "", mp4->nalu->length, (int)mp4->nalu->size, mp4->atom->size);

	return 1;
}

int mp4_reader_skip_nalu_data(mp4_reader *mp4){
	return mp4_reader_read_nalu_data(mp4, NULL, (int)mp4->nalu->size);
}

// return bytes read
int mp4_reader_read_nalu_data(mp4_reader *mp4, void *buf, int size){
	size = (size <= mp4->nalu->size)? size : (int)mp4->nalu->size;
	if(size <= 0){
		return 0;
	}
	int len;
	len = mp4->input_cb(mp4, buf, size);
	if(len <= 0){
		return 0;
	}
	mp4->nalu->size -= size;
	return size;
}

int mp4_reader_enter_sub_atom(mp4_reader *mp4){
	if(mp4->depth >= MAX_ATOM_DEPTH -1){
		return -1;
	}
	mp4->depth ++;
	mp4->atom = &mp4->subs[mp4->depth];
	mp4->atom->length = 0;
	mp4->atom->size = 0;
	return 0;
}

int mp4_reader_leave_sub_atom(mp4_reader *mp4){
	if(mp4->depth <= 1){
		return -1;
	}
	mp4->depth --;
	mp4->atom = &mp4->subs[mp4->depth];
	return 0;
}

static void parse_params(char *buf, int size, void **sps, int *sps_size, void **pps, int *pps_size);

// the simple way
int mp4_file_parse_params(const char *filename, void **sps, int *sps_size, void **pps, int *pps_size){
	*sps = NULL;
	*pps = NULL;
	*sps_size = 0;
	*pps_size = 0;
	
	mp4_reader *mp4 = mp4_file_open(filename);
	if(!mp4){
		log_debug("failed to open %s", filename);
		return -1;
	}
	
	int ret = 0;
	uint32_t type;
	while(mp4_reader_next_atom(mp4)){
		type = mp4->atom->type;
		if(type == 'moov'){
			int size = (int)mp4->atom->size;
			char *buf = malloc(size);
			int len = mp4_reader_read_atom_data(mp4, buf, size);
			if(len != size){
				log_debug("failed to read 'moov', request: %d, return: %d", size, len);
				ret = -1;
			}else{
				//
				parse_params(buf, size, sps, sps_size, pps, pps_size);
				if(!sps_size || !pps_size){
					return ret = -1;
				}
			}
			free(buf);
			break;
		}
	}
	
	mp4_reader_free(mp4);
	return ret;
}

inline
static void* memdup(char *buf, int size){
	void *p = malloc(size);
	memcpy(p, buf, size);
	return p;
}

inline
static uint32_t ptonl(void *p){
	return __builtin_bswap32(*(uint32_t *)p);
}

inline
static uint16_t ptons(void *p){
	return __builtin_bswap16(*(uint16_t *)p);
}

static void parse_params(char *buf, int size, void **sps, int *sps_size, void **pps, int *pps_size){
	char *p = buf;
	char *end = buf + size;
	while(p < end){
		uint32_t type = ptonl(p);
		
		if(type == 'avcC'){
			p += 4 ; // skip 'avcC'
			p += 4 ; // skip avcC header
			p += 2;  // skip skip length and sps count
			
			char *data;
			uint16_t len;
			
			len = ptons(p);
			p += 2;
			data = p;
			p += len;
			*sps = memdup(data, size);
			*sps_size = len;
			
			p += 1; // skip pps count
			
			len = ptons(p);
			p+= 2;
			data = p;
			*pps = memdup(data, size);
			*pps_size = len;
			
			break;
		}
		++p;
	}
}

// TESTING
#if 0

void read_mp4(const char *filename);

int main(int argc, char **argv){
	read_mp4("../../Downloads/m1.mp4");
	read_mp4("../../Downloads/params.mp4");
	read_mp4("../../Downloads/capture.mp4");
	return 0;
}

void read_mp4(const char *filename){
	mp4_reader *mp4 = mp4_file_open(filename);
	if(!mp4){
		return;
	}
	while(mp4_reader_next_atom(mp4)){
		uint32_t type;
		long size;
		type = mp4->atom->type;
		size = mp4->atom->size;
		if(type == 'moov'){
			mp4_reader_enter_sub_atom(mp4);
			mp4_reader_next_atom(mp4);
			type = mp4->atom->type;
			size = mp4->atom->size;
			if(type == 'mvhd'){
				mp4_reader_next_atom(mp4);
				type = mp4->atom->type;
				size = mp4->atom->size;
				if(type == 'trak'){
					mp4_reader_enter_sub_atom(mp4);
					mp4_reader_next_atom(mp4);
					mp4_reader_leave_sub_atom(mp4);
				}
			}
			mp4_reader_leave_sub_atom(mp4);
		}
		if(type == 'mdat'){
			while(mp4_reader_next_nalu(mp4)){
				//
			}
		}
	}
	mp4_reader_free(mp4);
	printf("\n");
}

#endif