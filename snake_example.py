import sys, json, numpy as np # must ensure that whatever this script relies on is installed on all cluster machines that could run this

def main():
    lines = ''
    for ln in sys.stdin.readlines(): lines += ln
    inp = json.loads(lines)
    arr = np.array(inp)
    res = np.sum(arr)
    print res

if __name__ == '__main__':
    main()