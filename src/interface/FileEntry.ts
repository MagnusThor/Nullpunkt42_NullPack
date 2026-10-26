
export interface FileEntry {
  path: string;
  size: number;
  origSize: number;
  compressed: boolean;
  mime: string;
}


export interface BundleHeaderMeta {
  runnerFile: string;
  created: number;
}