import argparse
import os


def main():
    parser = argparse.ArgumentParser(
        description="ファイルを読み込みます（最大8192バイト）"
    )
    parser.add_argument("file", help="読み込むファイルのパス")
    args = parser.parse_args()

    # ファイルの存在確認
    if not os.path.isfile(args.file):
        raise FileNotFoundError(f"ファイルが見つかりません: {args.file}")

    # サイズチェック
    size = os.path.getsize(args.file)
    if size > 8192:
        raise Exception(
            "指定されたファイルサイズが大きすぎます。8192バイトに抑えてください"
        )


if __name__ == "__main__":
    main()
