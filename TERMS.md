# Terms and privacy

*Last updated: 18 November 2026*

## Terms of use

NuVa is free, open-source software, published under the [MIT License](https://github.com/martinsmdnuno/nuva/blob/main/LICENSE). You may use, copy, change and share it under that license.

NuVa is provided **as is, without warranty of any kind**. Its author is not liable for any damage or loss that comes from using it, including to your files, your music library or your equipment.

You are responsible for the music you play with NuVa and for having the right to play it.

## Privacy

NuVa has no account, no tracking and no ads. It doesn't collect, sell or share personal data. Your settings, the queue and where you left off stay on your Mac. Nothing about how you use NuVa is sent anywhere unless you say yes to the anonymous counts described below.

NuVa only connects to the internet in these cases:

- **Your Jellyfin server**, if you add one: to browse and play your music. Your password is kept in the macOS Keychain.
- **MusicBrainz and the Cover Art Archive**, only when **Show Artwork** is on and a folder has no image of its own: NuVa sends the artist and album names it reads from the folder names, to find the album's cover. No other information is sent. Covers are kept on your Mac.
- **MusicBrainz and the Cover Art Archive**, when you insert an audio CD that NuVa hasn't seen before: NuVa sends the disc's table of contents (its disc ID and track lengths), to find the album, artist and track names, which a CD doesn't carry. With **Show Artwork** on, it also fetches that album's cover. Names and covers are kept on your Mac, so a known disc doesn't go online again.
- **GitHub**, at most once a day, to check whether there is a newer version of NuVa. Nothing is downloaded or installed automatically.
- **The author's server (nuva.martinsnuno.com)**, only if you turned on **Send Anonymous Use and Failures**. NuVa asks once, and the answer is no unless you choose yes. With it on, about once a day NuVa sends counts: how many times each feature was used, how the app is set (the skin, the font, which options are on), which kinds of failure happened (a code such as "track skipped, no connection") and, after a crash, the crash report macOS made, which says where in the app it stopped. The app's version and the macOS version go with them. It never sends the names of folders, files or servers, anything about your music, or any identifier of you or your Mac. The server writes down no IP address, keeps the counts for a year and crash reports for 90 days, and the author reads them only to decide what to fix and what to build. You can turn it off at any time in the NuVa menu, which also deletes what was counted and not yet sent.

NuVa keeps a log of failures on your Mac, to help when something goes wrong (NuVa ▸ Show Error Log). The log may name your folders and files, and it never leaves your Mac.

**NuVa for Android TV** goes online in the same cases: your Jellyfin server, MusicBrainz and the Cover Art Archive (only with **Show Artwork** on), and GitHub at most once a day. When you choose **Update to X** in its menu, it downloads that version from the release on GitHub and hands it to Android's installer, which asks you to confirm; it never does this by itself. It signs in to Jellyfin with your password once and keeps only the server's access token, never the password. Its settings, the queue and where you left off stay on the TV.

**NuVa for Windows** goes online in the same cases as on the Mac: your Jellyfin server, MusicBrainz and the Cover Art Archive (with **Show Artwork** on, and for an audio CD it hasn't seen before), and GitHub at most once a day. Your Jellyfin password is kept in Windows Credential Manager. Its settings stay in your user's AppData folder, and covers, CD names and a log of what the app did (for when something goes wrong; it is only sent if you send it) stay on your computer.

NuVa for Android TV and NuVa for Windows don't have the anonymous counts: they send nothing about how they are used.

These services have their own terms and privacy policies: [MusicBrainz](https://metabrainz.org/privacy), [Internet Archive](https://archive.org/about/terms.php) (which hosts the Cover Art Archive) and [GitHub](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement).

## Album artwork

Album covers belong to their owners. NuVa shows them only on your Mac, as a reference for the music you already have. It never writes into your music folders.

## Third parties

Fonts: Inter, IBM Plex, DM Sans and DM Mono, and Share Tech, under the SIL Open Font License. NuVa plays audio through Apple's own frameworks; NuVa for Android TV through Android's own decoders, with AndroidX Media3; NuVa for Windows through Windows' own Media Foundation and audio engine.

## Contact

Questions and problems: [github.com/martinsmdnuno/nuva/issues](https://github.com/martinsmdnuno/nuva/issues).

---

# Termos e privacidade

*Última atualização: 18 de novembro de 2026*

## Termos de utilização

A NuVa é software gratuito e de código aberto, publicado com a [licença MIT](https://github.com/martinsmdnuno/nuva/blob/main/LICENSE). Podes usá-la, copiá-la, alterá-la e partilhá-la nos termos dessa licença.

A NuVa é fornecida **tal como está, sem qualquer garantia**. O autor não é responsável por danos ou perdas que resultem do seu uso, incluindo nos teus ficheiros, na tua biblioteca de música ou no teu equipamento.

És responsável pela música que tocas com a NuVa e por teres o direito de a tocar.

## Privacidade

A NuVa não tem conta, rastreio nem publicidade. Não recolhe, vende nem partilha dados pessoais. As tuas definições, a fila e o ponto onde ficaste ficam no teu Mac. Nada sobre a forma como usas a NuVa é enviado para lado nenhum, a não ser que digas que sim às contagens anónimas descritas abaixo.

A NuVa só se liga à internet nestes casos:

- **O teu servidor Jellyfin**, se adicionares um: para navegar e tocar a tua música. A palavra-passe fica no Porta-chaves do macOS.
- **MusicBrainz e Cover Art Archive**, só com **Mostrar capas** ligado e quando uma pasta não tem imagem própria: a NuVa envia o nome do artista e do álbum que lê dos nomes das pastas, para encontrar a capa. Não é enviada mais nenhuma informação. As capas ficam guardadas no teu Mac.
- **MusicBrainz e Cover Art Archive**, quando metes um CD áudio que a NuVa ainda não conhece: a NuVa envia o índice do disco (o seu disc ID e a duração das faixas), para encontrar os nomes do álbum, do artista e das faixas, que um CD não traz. Com **Mostrar capas** ligado, vai também buscar a capa desse álbum. Os nomes e as capas ficam guardados no teu Mac, por isso um disco conhecido não volta a ir à internet.
- **GitHub**, no máximo uma vez por dia, para saber se há uma versão nova da NuVa. Nada é descarregado nem instalado automaticamente.
- **O servidor do autor (nuva.martinsnuno.com)**, só se ligaste **Enviar uso e falhas anónimos**. A NuVa pergunta uma vez, e a resposta é não a menos que escolhas sim. Com isto ligado, cerca de uma vez por dia a NuVa envia contagens: quantas vezes cada função foi usada, como a app está configurada (a skin, a fonte, que opções estão ligadas), que tipos de falha aconteceram (um código como "faixa saltada, sem ligação") e, depois de um crash, o relatório que o macOS fez, que diz em que ponto da app ela parou. Com elas vão a versão da app e a versão do macOS. Nunca envia nomes de pastas, ficheiros ou servidores, nada sobre a tua música, nem qualquer identificador teu ou do teu Mac. O servidor não regista endereços IP, guarda as contagens durante um ano e os relatórios de crash durante 90 dias, e o autor lê-os apenas para decidir o que corrigir e o que construir. Podes desligar a qualquer momento no menu NuVa, o que também apaga o que foi contado e ainda não enviado.

A NuVa guarda no teu Mac um registo de falhas, para ajudar quando algo corre mal (NuVa ▸ Mostrar registo de erros). O registo pode ter nomes das tuas pastas e ficheiros, e nunca sai do teu Mac.

A **NuVa para Android TV** vai à internet nos mesmos casos: o teu servidor Jellyfin, o MusicBrainz e o Cover Art Archive (só com **Mostrar capas** ligado) e o GitHub no máximo uma vez por dia. Quando escolhes **Atualizar para X** no menu, descarrega essa versão da release no GitHub e entrega-a ao instalador do Android, que te pede para confirmar; nunca o faz sozinha. Entra no Jellyfin com a tua palavra-passe uma vez e guarda apenas a chave de acesso do servidor, nunca a palavra-passe. As definições, a fila e o ponto onde ficaste ficam na TV.

A **NuVa para Windows** vai à internet nos mesmos casos que no Mac: o teu servidor Jellyfin, o MusicBrainz e o Cover Art Archive (com **Mostrar capas** ligado, e para um CD áudio que ainda não conhece) e o GitHub no máximo uma vez por dia. A palavra-passe do Jellyfin fica no Gestor de Credenciais do Windows. As definições ficam na pasta AppData do teu utilizador, e as capas, os nomes dos CDs e um registo do que a app fez (para quando algo corre mal; só é enviado se tu o enviares) ficam no teu computador.

A NuVa para Android TV e a NuVa para Windows não têm as contagens anónimas: não enviam nada sobre a forma como são usadas.

Estes serviços têm os seus próprios termos e políticas de privacidade: [MusicBrainz](https://metabrainz.org/privacy), [Internet Archive](https://archive.org/about/terms.php) (que aloja o Cover Art Archive) e [GitHub](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement).

## Capas dos álbuns

As capas pertencem aos seus donos. A NuVa mostra-as apenas no teu Mac, como referência para a música que já tens. Nunca escreve nas tuas pastas de música.

## Terceiros

Fontes: Inter, IBM Plex, DM Sans e DM Mono, e Share Tech, com a SIL Open Font License. A NuVa toca áudio através das frameworks da própria Apple; a NuVa para Android TV através dos descodificadores do próprio Android, com o AndroidX Media3; a NuVa para Windows através do Media Foundation e do motor de áudio do próprio Windows.

## Contacto

Dúvidas e problemas: [github.com/martinsmdnuno/nuva/issues](https://github.com/martinsmdnuno/nuva/issues).
