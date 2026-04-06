# ラボ開発環境（ネットワーク構成）

個人ラボの開発・検証用ネットワーク構成を Mermaid で示します。物理接続・論理データフロー・管理レイヤを一枚にまとめています。

```mermaid
graph TD
    %% 外部接続・クラウド
    Internet((10G 光回線)) --- ONU[10G ONU]
    Cloudflare{{Cloudflare R2<br/>S3互換ストレージ}}

    subgraph Core_Infrastructure [基盤管理：RTX1300]
        ONU --- RTX[ヤマハ RTX1300<br/>10Gメインルーター]

        %% RTX1300の内部機能
        RTX --- DHCP[DHCP: 固定IP割当]
        RTX --- DNS[DNS: 内部名前解決]
        RTX --- Syslog[Syslog: ログ集約先]
    end

    subgraph HighSpeed_10G_Zone [10G 開発・高速ストレージ]
        %% 10G SFP+ DAC接続
        RTX ===|10G SFP+ DAC| Mik[MikroTik CRS305]

        %% 高速デバイス
        Mik --- NAS[(Synology NAS<br/>Assets蓄積 / Docker)]
        Mik --- MainPC[メイン業務PC<br/>10G NIC]
        Mik --- WiFi7[TP-Link WiFi 7<br/>APモード / 10G]
    end

    subgraph Management_Layer [管理・監視サーバー：Container]
        %% NAS上のDocker等で稼働
        NAS --- Gitea[Gitea: ローカルGit]
        NAS --- Grafana[Grafana: ログ監視可視化]
        NAS --- Registry[Container Registry]
    end

    subgraph Multi_Platform_Test [1G テスト・デバッグ環境]
        %% ヤマハスイッチでの管理
        RTX ---|1G LAN1| SWX[ヤマハ SWX2210-8G]

        %% テスト機群
        SWX --- Win[Windows Server]
        SWX --- Mac[Mac mini]
        SWX --- Lux[Linux Server]

        %% 低速シミュレーション
        SWX ---|Port 8: 800kbps Shaping| Pi4[Raspberry Pi 4<br/>低速モバイル擬似環境]
    end

    %% 論理的なデータの流れ
    MainPC -.->|Assets| NAS
    NAS -.->|Sync| Cloudflare

    %% テスト機からのアクセス
    Win & Mac & Lux & Pi4 ==>|Load Assets| NAS
    Win & Mac & Lux & Pi4 -.->|Send Logs| Syslog
```

運用設計（VLAN・FW・ログ・NAS のたたき台）は [lab-environment-operations-stub.md](./lab-environment-operations-stub.md) を参照してください。
