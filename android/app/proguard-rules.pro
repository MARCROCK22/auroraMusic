# Commons Compress creates registered ZIP extra-field implementations reflectively.
-keep class org.apache.commons.compress.archivers.zip.ExtraFieldUtils { *; }
-keep class * implements org.apache.commons.compress.archivers.zip.ZipExtraField { <init>(); }
