class CephFuse < Formula
  desc "Ceph FUSE"
  homepage "https://ceph.com"
  url "https://github.com/ceph/ceph.git", :using => :git, :tag => "v14.2.5", :revision => "ad5bd132e1492173c85fda2cc863152730b16a92"
  version "nautilus-14.2.5"

  bottle do
    root_url "https://github.com/ailabstw/homebrew-ceph-fuse/releases/download/nautilus-14.2.5/"
    sha256 "2e1856c6e2885d5d5985028f879f29896848da38aafc84ed2076904d6f5bfb86" => :catalina
  end

  depends_on "openssl"
  depends_on "cmake" => :build
  depends_on "cython" => :build
  depends_on "pkg-config" => :build
  depends_on "boost" => :build
  depends_on "llvm" => :build
  depends_on "nss"
  depends_on "python@2"
  depends_on "yasm"

  patch :DATA

  def install
    # This is a poor work around since Formula doesn't suppport dependency on Brew Cask
    # system "brew", "cask", "install", "osxfuse"

    ENV["CC"] = "#{Formula["llvm"].bin}/clang"
    ENV["CXX"] = "#{Formula["llvm"].bin}/clang++"
    ENV["PKG_CONFIG_PATH"] = "#{Formula["nss"].opt_lib}/pkgconfig"
    ENV["PYTHONPATH"] = "#{Formula["cython"].opt_libexec}/lib/python3.7/site-packages"
    args = %W[
      -DPYTHON_INCLUDE_DIR=#{Formula["python@2"].prefix}/Frameworks/Python.framework/Headers
      -DDIAGNOSTICS_COLOR=always
      -DOPENSSL_ROOT_DIR=#{Formula["openssl"].prefix}
      -DBOOST_ROOT=#{Formula["boost"].prefix}
      -DWITH_FUSE=ON
      -DWITH_SYSTEM_BOOST=ON
      -DWITH_SYSTEM_ROCKSDB=OFF
      -DWITH_LEVELDB=OFF
      -DWITH_BABELTRACE=OFF
      -DWITH_BLUESTORE=OFF
      -DWITH_CCACHE=OFF
      -DWITH_CEPHFS=OFF
      -DWITH_KRBD=OFF
      -DWITH_LIBCEPHFS=OFF
      -DWITH_LTTNG=OFF
      -DWITH_LZ4=OFF
      -DWITH_MANPAGE=OFF
      -DWITH_MGR=OFF
      -DWITH_MGR_DASHBOARD_FRONTEND=OFF
      -DWITH_RBD=OFF
      -DWITH_RADOSGW=OFF
      -DWITH_RDMA=OFF
      -DWITH_SPDK=OFF
      -DWITH_SYSTEMD=OFF
      -DWITH_TESTS=OFF
      -DWITH_XFS=OFF
      -DENABLE_SHARED=OFF
      -DWITH_OPENLDAP=OFF
      -DWITH_KVS=OFF
    ]
    mkdir "build" do
      system "cmake", "..", *args, *std_cmake_args
      system "make", "ceph-fuse"
      bin_cephfuse = "bin/ceph-fuse"
      lib_cephcommon = "lib/libceph-common.0.dylib"
      MachO.open(bin_cephfuse).linked_dylibs.each do |dylib|
        unless dylib.start_with?("/tmp/")
          next
        end
        MachO::Tools.change_install_name(bin_cephfuse, dylib, "#{lib}/#{dylib.split('/')[-1]}")
      end
      bin.install bin_cephfuse
      lib.install lib_cephcommon
    end
  end

  test do

    system "#{bin}/ceph-fuse", "--version"
  end
end

__END__
diff --git a/src/CMakeLists.txt b/src/CMakeLists.txt
index 28ec9835f8..84ff0a3d51 100644
--- a/src/CMakeLists.txt
+++ b/src/CMakeLists.txt
@@ -171,7 +171,7 @@ if(${ENABLE_COVERAGE})
   list(APPEND EXTRALIBS gcov)
 endif(${ENABLE_COVERAGE})
 
-include_directories(${NSS_INCLUDE_DIR} ${NSPR_INCLUDE_DIR})
+include_directories(${NSS_INCLUDE_DIR} ${NSPR_INCLUDE_DIR} ${OPENSSL_INCLUDE_DIR})
 
 set(GCOV_PREFIX_STRIP 4)
 
diff --git a/src/auth/KeyRing.cc b/src/auth/KeyRing.cc
index 41e440455c..2c025483e0 100644
--- a/src/auth/KeyRing.cc
+++ b/src/auth/KeyRing.cc
@@ -206,12 +206,12 @@ void KeyRing::decode(bufferlist::const_iterator& bl) {
   __u8 struct_v;
   auto start_pos = bl;
   try {
+    decode_plaintext(start_pos);
+    } catch (...) {
+    keys.clear();
     using ceph::decode;
     decode(struct_v, bl);
     decode(keys, bl);
-  } catch (buffer::error& err) {
-    keys.clear();
-    decode_plaintext(start_pos);
   }
 }
 
diff --git a/src/common/ceph_time.cc b/src/common/ceph_time.cc
index f097e81425..672f4f7199 100644
--- a/src/common/ceph_time.cc
+++ b/src/common/ceph_time.cc
@@ -22,7 +22,7 @@
 #include <mach/mach.h>
 #include <mach/mach_time.h>
 
-#include <ostringstream>
+#include <sstream>
 
 #ifndef NSEC_PER_SEC
 #define NSEC_PER_SEC 1000000000ULL
diff --git a/src/common/compat.cc b/src/common/compat.cc
index 3380d1cd03..0f56f689f5 100644
--- a/src/common/compat.cc
+++ b/src/common/compat.cc
@@ -193,3 +193,25 @@ int sched_setaffinity(pid_t pid, size_t cpusetsize,
 }
 #endif
 
+#if defined(__APPLE__)
+
+#define SYSCTL_CORE_COUNT   "machdep.cpu.core_count"
+
+int sched_getaffinity(pid_t pid, size_t cpu_size, cpu_set_t *cpu_set)
+{
+  int32_t core_count = 0;
+  size_t  len = sizeof(core_count);
+  int ret = sysctlbyname(SYSCTL_CORE_COUNT, &core_count, &len, 0, 0);
+  if (ret) {
+    printf("error while get core count %d\n", ret);
+    return -1;
+  }
+  cpu_set->count = 0;
+  for (int i = 0; i < core_count; i++) {
+    cpu_set->count |= (1 << i);
+  }
+
+  return 0;
+}
+
+#endif /* __APPLE__ */
diff --git a/src/common/legacy_config_opts.h b/src/common/legacy_config_opts.h
index 79d9c1fa73..8ad559dfb6 100644
--- a/src/common/legacy_config_opts.h
+++ b/src/common/legacy_config_opts.h
@@ -603,7 +603,7 @@ OPTION(osd_objecter_finishers, OPT_INT)
 OPTION(osd_map_dedup, OPT_BOOL)
 OPTION(osd_map_cache_size, OPT_INT)
 OPTION(osd_map_message_max, OPT_INT)  // max maps per MOSDMap message
-OPTION(osd_map_message_max_bytes, OPT_SIZE)  // max maps per MOSDMap message
+OPTION(osd_map_message_max_bytes, OPT_U64)  // max maps per MOSDMap message
 OPTION(osd_map_share_max_epochs, OPT_INT)  // cap on # of inc maps we send to peers, clients
 OPTION(osd_inject_bad_map_crc_probability, OPT_FLOAT)
 OPTION(osd_inject_failure_on_pg_removal, OPT_BOOL)
@@ -1271,8 +1271,8 @@ OPTION(rados_tracing, OPT_BOOL) // true if LTTng-UST tracepoints should be enabl
 OPTION(nss_db_path, OPT_STR) // path to nss db
 
 
-OPTION(rgw_max_attr_name_len, OPT_SIZE)
-OPTION(rgw_max_attr_size, OPT_SIZE)
+OPTION(rgw_max_attr_name_len, OPT_U64)
+OPTION(rgw_max_attr_size, OPT_U64)
 OPTION(rgw_max_attrs_num_in_req, OPT_U64)
 
 OPTION(rgw_max_chunk_size, OPT_INT)
diff --git a/src/common/util.cc b/src/common/util.cc
index 3448eb2bfa..e857da79e0 100644
--- a/src/common/util.cc
+++ b/src/common/util.cc
@@ -137,6 +137,10 @@ static void distro_detect(map<string, string> *m, CephContext *cct)
 
 int get_cgroup_memory_limit(uint64_t *limit)
 {
+#if defined(__APPLE__)
+  // There is no such machanism for macos
+  return -errno;
+#else
   // /sys/fs/cgroup/memory/memory.limit_in_bytes
 
   // the magic value 9223372036854771712 or 0x7ffffffffffff000
@@ -164,6 +168,7 @@ int get_cgroup_memory_limit(uint64_t *limit)
 out:
   fclose(f);
   return ret;
+#endif /* __APPLE__ */
 }
 
 
diff --git a/src/include/compat.h b/src/include/compat.h
index 7c75dac2e1..6c26b48f53 100644
--- a/src/include/compat.h
+++ b/src/include/compat.h
@@ -49,6 +49,31 @@ int sched_setaffinity(pid_t pid, size_t cpusetsize,
 
 #endif /* __FreeBSD__ */
 
+#if defined(__APPLE__)
+
+#include <sys/types.h>
+#include <sys/sysctl.h>
+#include <stdio.h>
+
+#define SYSCTL_CORE_COUNT   "machdep.cpu.core_count"
+
+typedef struct cpu_set {
+  uint32_t    count;
+} cpu_set_t;
+
+static inline void
+CPU_ZERO(cpu_set_t *cs) { cs->count = 0; }
+
+static inline void
+CPU_SET(int num, cpu_set_t *cs) { cs->count |= (1 << num); }
+
+static inline int
+CPU_ISSET(int num, cpu_set_t *cs) { return (cs->count & (1 << num)); }
+
+int sched_getaffinity(pid_t pid, size_t cpu_size, cpu_set_t *cpu_set);
+
+#endif /* __APPLE__ */
+
 #if defined(__APPLE__) || defined(__FreeBSD__)
 /* Make sure that ENODATA is defined in the correct way */
 #ifdef ENODATA
