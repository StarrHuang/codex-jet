// 只读取指定进程的内核计数；不采集命令行、账户或会话内容。
#include <libproc.h>
#include <sys/resource.h>
#include <sys/proc_info.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <mach/mach_time.h>

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    char *end = NULL;
    long value = strtol(argv[1], &end, 10);
    if (!end || *end || value <= 0) return 2;
    struct rusage_info_v4 info = {0};
    if (proc_pid_rusage((int)value, RUSAGE_INFO_V4, (rusage_info_t *)&info) != 0) {
        fprintf(stderr, "proc_pid_rusage failed: %d\n", errno); return 1;
    }
    struct proc_taskinfo task = {0};
    if (proc_pidinfo((int)value, PROC_PIDTASKINFO, 0, &task, sizeof(task)) != sizeof(task)) return 1;
    mach_timebase_info_data_t timebase;
    if (mach_timebase_info(&timebase) != KERN_SUCCESS) return 1;
    // 内核 CPU 计数使用 mach ticks，统一换算为纳秒。
    unsigned long long cpu_ns = (unsigned long long)((__uint128_t)(info.ri_user_time + info.ri_system_time) * timebase.numer / timebase.denom);
    unsigned long long child_cpu_ns = (unsigned long long)((__uint128_t)(info.ri_child_user_time + info.ri_child_system_time) * timebase.numer / timebase.denom);
    printf("{\"pid\":%ld,\"cpu_ns\":%llu,\"child_cpu_ns\":%llu,\"rss_bytes\":%llu,\"footprint_bytes\":%llu,\"peak_footprint_bytes\":%llu,\"disk_read_bytes\":%llu,\"disk_write_bytes\":%llu,\"logical_write_bytes\":%llu,\"idle_wakeups\":%llu,\"interrupt_wakeups\":%llu,\"pageins\":%llu,\"threads\":%d,\"context_switches\":%d}\n",
        value, cpu_ns, child_cpu_ns,
        info.ri_resident_size, info.ri_phys_footprint, info.ri_lifetime_max_phys_footprint,
        info.ri_diskio_bytesread, info.ri_diskio_byteswritten, info.ri_logical_writes,
        info.ri_pkg_idle_wkups, info.ri_interrupt_wkups, info.ri_pageins,
        task.pti_threadnum, task.pti_csw);
    return 0;
}
