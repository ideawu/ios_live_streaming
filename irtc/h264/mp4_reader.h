#ifndef MP4_READER_H_
#define MP4_READER_H_

struct mp4_reader_t;
struct mp4_atom_t;
typedef struct mp4_reader_t mp4_reader;
typedef struct mp4_atom_t mp4_atom;

/**
 if buf is NULL, just skip size bytes.
 */
typedef int (*mp4_reader_input_cb)(mp4_reader *mp4, void *buf, int size);

struct mp4_atom_t{
	uint32_t length;
	uint32_t type;
	long size;
};

struct mp4_reader_t{
	void *user_data;
	mp4_reader_input_cb input_cb;

	int depth;
	mp4_atom *subs;
	mp4_atom *atom;
	mp4_atom *nalu;
};

mp4_reader* mp4_file_open(const char *filename);
/**
 if success, sps and pps pointed to allocated memory with data,
 and sps_size and pps_size is set.
 */
int mp4_file_parse_params(const char *filename, void **sps, int *sps_size, void **pps, int *pps_size);

mp4_reader* mp4_reader_init(void);
void mp4_reader_free(mp4_reader *mp4);
/**
 0: no atom
 1: atom available
 */
int mp4_reader_next_atom(mp4_reader *mp4);
int mp4_reader_skip_atom_data(mp4_reader *mp4);
int mp4_reader_read_atom_data(mp4_reader *mp4, void *buf, int size);
/**
 0: no nalu
 1: nalu available
 */
int mp4_reader_next_nalu(mp4_reader *mp4);
int mp4_reader_skip_nalu_data(mp4_reader *mp4);
int mp4_reader_read_nalu_data(mp4_reader *mp4, void *buf, int size);

int mp4_reader_enter_sub_atom(mp4_reader *mp4);
int mp4_reader_leave_sub_atom(mp4_reader *mp4);

#endif
