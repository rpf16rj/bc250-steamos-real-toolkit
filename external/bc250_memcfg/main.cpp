#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/io.h>

#define BYTE    __uint8_t
#define WORD    __uint16_t
#define DWORD   __uint32_t

//
// Signature Field
//
#define LINUX_TOOL_SIGNATURE        0x42435041
#define ABL_SIGNATURE               0x4C424124
#define CMOS_BAD_ERROR_CODE         0x42534D43
#define WATCH_DOG_TIMER_FIRED       0x46544457
#define CHECKSUM_ERROR_CODE         0x454B4843
#define SIGNATURE_ERROR_CODE        0x45474953

#pragma pack(push)
#pragma pack(1)
typedef struct
{
//  Length        Name       CMOS Offset     Value Range
// ------------------------------------------------------------------------------
    DWORD       Signature;  // 90h          See definition 'Signature Field'
    WORD        Checksum;   // 94h          16-bit byte sum value of the field offset
                            //              from 96h to ABh
    WORD        ClockSpeed; // 96h          [0x01C2 : 0x06D6] (450Mhz ~ 1750Mhz)] 
    BYTE        tCL;        // 98h          [0x08   : 0x21  ]
    BYTE        tRAS;       // 99h          [0x15   : 0x3A  ]
    BYTE        tRCDRD;     // 9Ah          [0x08   : 0x1B  ]
    BYTE        tRCDWR;     // 9Bh          [0x08   : 0x1B  ]
    BYTE        tRCAb;      // 9Ch          [0x28   : 0x5A  ]
    BYTE        tRCPb;      // 9Dh          [0x00   : 0x0B  ]
    BYTE        tRPAb;      // 9Eh          [0x08   : 0x1B  ]
    BYTE        tRPPb;      // 9Fh          [0x00   : 0x0B  ]
    BYTE        tRRDS;      // A0h          [0x04   : 0x0C  ]
    BYTE        tRRDL;      // A1h          [0x04   : 0x0C  ]
    BYTE        tRTP;       // A2h          [0x00   : 0x0E  ]
    BYTE        tFAW;       // A3h          [0x04   : 0x22  ]
    WORD        tREF;       // A4h          [0x0000 : 0xFFFF]
    WORD        RFCPb;      // A6h          [0x0000 : 0xFFFF]
    WORD        tRFC;       // A8h          [0x0000 : 0xFFFF]
    WORD        UMA_SIZE;   // AAh          UMA Frame Buffer size in MB (16M alignment)
} MemConf_t;
#pragma pack(pop)

bool CheckPrivilege(void);

void IoBaseWriteByte(BYTE Port, BYTE Value);
BYTE IoBaseReadByte(BYTE Port);
BYTE IoIndexReadByte(BYTE IndexPort, BYTE DataPort, BYTE Offset);
void IoIndexWriteByte(BYTE IndexPort, BYTE DataPort, BYTE Offset, BYTE Value);

WORD CalcChecksum(BYTE* buf, int bufsize);

void DumpBuffer(BYTE* buf, int bufsize);

//
// Read data from configuration space
//
void DumpMemCfg(BYTE* Config, int Size);
//
// Write data to configuration space
//
void WriteMemCfg(BYTE* Config, int Size);


WORD page_size;
BYTE cmos_io_port;
BYTE config_space_offset_start;
BYTE config_space_size;

int main(int argc, char** argv)
{
    if (!CheckPrivilege()) {       
        printf("Please run as root!\n");
        return 1;
    }

    page_size = 0x100;
    cmos_io_port = 0x72;
    config_space_offset_start = 0x90;
    config_space_size = sizeof(MemConf_t);

    BYTE buf[page_size] = { 0 }; 
    MemConf_t* pMemConf = (MemConf_t*)&buf[config_space_offset_start];

    int n;
    for (n = 0; n < page_size; n++) {
        buf[n] = IoIndexReadByte(cmos_io_port, cmos_io_port + 1, n);
    }

    if (argc == 3) {
        int val = atoi(argv[2]);
        char *arg = argv[1];
        void *ptr = NULL;
        int size = 0;
        const char *n,*name;
	n="ClockSpeed";if (strcmp(arg,n) == 0 && val>300 && val < 2000) { ptr = &pMemConf->ClockSpeed; size = 2; name=n;}
	n="tCL";if (strcmp(arg,n) == 0 && val>0) { ptr = &pMemConf->tCL; size = 1; name=n;}
	n="tRAS";if (strcmp(arg,n) == 0 && val>0) { ptr = &pMemConf->tRAS; size = 1; name=n;}
	n="tRCDRD";if (strcmp(arg,n) == 0 && val>0) { ptr = &pMemConf->tRCDRD; size = 1; name=n;}
	n="tRCDWR";if (strcmp(arg,n) == 0 && val>0) { ptr = &pMemConf->tRCDWR; size = 1; name=n;}
	n="tRCAb";if (strcmp(arg,n) == 0 && val>0) { ptr = &pMemConf->tRCAb; size = 1; name=n;}
	n="tRCPb";if (strcmp(arg,n) == 0) { ptr = &pMemConf->tRCPb; size = 1; name=n;}
	n="tRPAb";if (strcmp(arg,n) == 0 && val>0) { ptr = &pMemConf->tRPAb; size = 1; name=n;}
	n="tRPPb";if (strcmp(arg,n) == 0) { ptr = &pMemConf->tRPPb; size = 1; name=n;}
	n="tRRDS";if (strcmp(arg,n) == 0 && val>0) { ptr = &pMemConf->tRRDS; size = 1; name=n;}
	n="tRRDL";if (strcmp(arg,n) == 0 && val>0) { ptr = &pMemConf->tRRDL; size = 1; name=n;}
	n="tRTP";if (strcmp(arg,n) == 0) { ptr = &pMemConf->tRTP; size = 1; name=n;}
	n="tFAW";if (strcmp(arg,n) == 0 && val>0) { ptr = &pMemConf->tFAW; size = 1; name=n;}
	n="tREF";if (strcmp(arg,n) == 0 && val>0) { ptr = &pMemConf->tREF; size = 2; name=n;}
	n="RFCPb";if (strcmp(arg,n) == 0 && val>0) { ptr = &pMemConf->RFCPb; size = 2; name=n;}
	n="tRFC";if (strcmp(arg,n) == 0 && val>0) { ptr = &pMemConf->tRFC; size = 2; name=n;}
        n="UMA_SIZE";if (strcmp(arg,n) == 0 && val>=256 && val < 16384) { ptr = &pMemConf->UMA_SIZE; size = 2; name=n; val&=0xFFF0;}
        if (ptr != NULL){
    	    BYTE *bptr;
    	    WORD *wptr;
    	    switch(size) {
    		case 1:
        		bptr = (BYTE*) ptr;
        		if (val>255) val= -1; else *bptr = (BYTE) val;
        		break;
    		case 2:
        		wptr = (WORD*) ptr;
        		if (val>65535) val= -1; else  *wptr = (WORD) val;
        		break;
    		default:
        		val = -1;
    	    }
            if (val > -1) {
        	printf("setting %s to %d\n",name,val);
        	WriteMemCfg((BYTE*)pMemConf, config_space_size);
            }
        }
        return 0;
    }
    
    DumpBuffer(buf, page_size);
    DumpMemCfg(buf + config_space_offset_start, config_space_size); 

    return 0;
}

bool CheckPrivilege(void)
{
    return iopl(3) ? false : true;
}

void IoBaseWriteByte(BYTE Port, BYTE Value)
{
    outb(Value, Port);
}

BYTE IoBaseReadByte(BYTE Port)
{
    return inb(Port);
}

BYTE IoIndexReadByte(BYTE IndexPort, BYTE DataPort, BYTE Offset)
{
    IoBaseWriteByte(IndexPort, Offset);
    return IoBaseReadByte(DataPort);
}

void IoIndexWriteByte(BYTE IndexPort, BYTE DataPort, BYTE Offset, BYTE Value)
{
    IoBaseWriteByte(IndexPort, Offset);
    IoBaseWriteByte(DataPort, Value);
}

WORD CalcChecksum(BYTE* buf, int bufsize)
{
    DWORD Index;
    WORD  Checksum;

    Checksum = 0;
    for (Index = 0; Index < bufsize; Index++) {
        Checksum += (*((BYTE*)buf + Index));
    }

    return Checksum;
}

void DumpBuffer(BYTE* buf, int bufsize)
{
    int n;
    printf("     00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F\n");
    printf("----------------------------------------------------\n");
    printf("0000 ");
    for (n = 0; n < bufsize; n++) {
        if (n != 0 && (n % 16) == 0){
            printf("\n%04X ", n / 16);
        }
        printf("%02X ", *(buf + n));
    }
    printf("\n");
}

void DumpMemCfg(BYTE* Config, int Size)
{
    MemConf_t* pMemConf = (MemConf_t*)Config;

    printf("\n");
    printf("Signature    : 0x%08X", pMemConf->Signature);
    if (pMemConf->Signature == LINUX_TOOL_SIGNATURE) {
        printf(" (LINUX_TOOL_SIGNATURE)\n");
    } else if (pMemConf->Signature == ABL_SIGNATURE) {
        printf(" (ABL_SIGNATURE)\n");
    } else if (pMemConf->Signature == CMOS_BAD_ERROR_CODE) {
        printf(" (CMOS_BAD_ERROR_CODE)\n");
    } else if (pMemConf->Signature == WATCH_DOG_TIMER_FIRED) {
        printf(" (WATCH_DOG_TIMER_FIRED)\n");
    } else if (pMemConf->Signature ==  CHECKSUM_ERROR_CODE) {
        printf(" (CHECKSUM_ERROR_CODE)\n");
    } else if (pMemConf->Signature == SIGNATURE_ERROR_CODE) {
        printf(" (SIGNATURE_ERROR_CODE)\n");
    } else {
        printf(" (UNKNOWN_SIGNATURE)\n");
    }
    printf("Checksum     : 0x%04X\n", pMemConf->Checksum);
    //printf("             : 0x%04X\n", CalChecksum(Config+6, 20));
    printf("ClockSpeed=%d\n", pMemConf->ClockSpeed);
    printf("tCL=%02d\n", pMemConf->tCL);
    printf("tRAS=%02d\n", pMemConf->tRAS);
    printf("tRCDRD=%02d\n", pMemConf->tRCDRD);
    printf("tRCDWR=%02d\n", pMemConf->tRCDWR);
    printf("tRCAb=%02d\n", pMemConf->tRCAb);
    printf("tRCPb=%02d\n", pMemConf->tRCPb);
    printf("tRPAb=%02d\n", pMemConf->tRPAb);
    printf("tRPPb=%02d\n", pMemConf->tRPPb);
    printf("tRRDS=%02d\n", pMemConf->tRRDS);
    printf("tRRDL=%02d\n", pMemConf->tRRDL);
    printf("tRTP=%02d\n", pMemConf->tRTP);
    printf("tFAW=%02d\n", pMemConf->tFAW);
    printf("tREF=%04d\n", pMemConf->tREF);
    printf("RFCPb=%04d\n", pMemConf->RFCPb);
    printf("tRFC=%04d\n", pMemConf->tRFC);
    printf("UMA_SIZE=%04d\n", pMemConf->UMA_SIZE);
}

void WriteMemCfg(BYTE* Config, int Size)
{    
    int Offset, Index;
    MemConf_t* pMemCfg = (MemConf_t*)Config;

    pMemCfg->Signature = LINUX_TOOL_SIGNATURE;
    pMemCfg->Checksum = CalcChecksum(Config + 6, sizeof(MemConf_t) - 6);
    
    Index = 0;
    Offset = config_space_offset_start;
    while(Index < config_space_size) {
        IoIndexWriteByte(cmos_io_port, cmos_io_port + 1, Offset + Index, *(Config + Index));
        Index++;
    }
}

