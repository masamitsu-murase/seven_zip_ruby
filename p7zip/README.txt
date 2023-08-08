https://translate.google.com/?sl=ja

 extract.sh は、 seven_zip_ruby が取り込んでいるプログラム ソースとバイナリーを新しいバージョンに置き換えるスクリプトです。スクリプトに記述し公開する目的は次の２つです。

  o 取り込み手順を明らかにする
  o コミットされたファイルが細工されていないことを証明する

 seven_zip_ruby は p7zip のソースの一部と 7zip の dll をリポジトリに保存しています。外部ソースの更新にあわせ、取り込まれたソースも更新する必要があります。

 extract.sh の実行には、次のアーカイブが必要です。配布元から取得し、スクリプトと同じディレクトリーに保存します。

アーカイブ：
p7zip_16.02_src_all.tar.bz2
p7zip_16.02+dfsg-7.debian.tar.xz
7z1900.exe
7z1900-x64.exe

配布元：
https://sourceforge.net/projects/p7zip/
https://packages.debian.org/ja/sid/p7zip
https://sourceforge.net/projects/sevenzip/files/

スクリプトを実行する前に、 ext ディレクトリーにある C, CPP, p7zip ディレクトリーを削除してください。 extract.sh は ext ディレクトリーにある p7zip ディレクトリーを上書きしません。

 lib/seven_zip_ruby にある *.dll, *.sfx は上書きします。 ext ディレクトリーでないことに注意してください。 seven_zip_archive.so はこの場所にある dll を使用します。

準備ができたら bash extract.sh を実行します。


