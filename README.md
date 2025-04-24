# Kubernetes 部署 Nextcloud + OnlyOffice

​	这个代码仓库包含了在 Kubernetes 环境中部署 Nextcloud 以及 OnlyOffice 所需的所有配置文件和相关资源，旨在实现 Nextcloud 应用能够便捷地打开和编辑 Office 文档（如 Word、Excel、PowerPoint 等）的功能，为用户提供个性化的文档管理和编辑体验。

## 一、项目概述

本项目在Kubernetes集群中部署完整的NextCloud云存储解决方案，集成OnlyOffice文档协作服务，包含以下组件：

- NextCloud应用（PHP-FPM）
- MariaDB数据库
- Nginx反向代理
- OnlyOffice Document Server
- NFS持久化存储

**文件结构说明**



```
.
├── 00-run.sh                  # 部署脚本（需自行添加执行权限）
├── 01-ns-nextcloud.yaml       # 命名空间配置
├── 02-pod-pvc.yaml            # 测试Pod的PVC（可忽略）
├── 03-db-deployment.yaml      # MariaDB数据库部署
├── 04-db-svc.yaml             # 数据库服务
├── 05-nextcloud-pvc.yaml      # NextCloud主存储PVC
├── 06-edit-config.php-cm.yaml # NextCloud配置修改脚本
├── 07-nc-deployment.yaml      # NextCloud应用部署
├── 08-nc-svc.yaml             # NextCloud服务
├── 09-onlyoffice.yaml         # OnlyOffice部署
├── 10-nginx-configmap.yaml    # Nginx配置
├── 11-nginx.yaml              # Nginx部署
└── onlyoffice.tar.gz          # OnlyOffice插件
```

**前置要求**

1. Kubernetes集群（v1.27+）
2. NFS CSI存储驱动（已配置storageClassName: nfs-csi）
3. 私有镜像仓库访问权限（harbor.yq.com）
4. DNS解析配置（nextcloud.yq.com指向Ingress IP）



## 二、部署步骤

#### 方法一：使用 `00-run.sh` 自动部署

```shell
# 克隆代码、进入项目
git clone https://gitee.com/qingcaihub/nextcloud-onlyoffice
cd nextcloud-onlyoffice

# 运行项目
bash 00-run.sh
```

```
# cat 00-run.sh
#!/bin/bash
# git clone https://gitee.com/qingcaihub/nextcloud-onlyoffice
# cd nextcloud-onlyoffice
for i in {01..11} ; do kubectl apply -f $i* ; done
sleep 200
kubectl exec -it -n nextcloud nextcloud-app-0 -- /bin/bash /tmp/run.sh
```

#### 方法二：手动部署

```
1. 创建命名空间
kubectl apply -f 01-ns-nextcloud.yaml

2. 部署数据库
kubectl apply -f 03-db-deployment.yaml
kubectl apply -f 04-db-svc.yaml

3. 部署持久化存储
kubectl apply -f 05-nextcloud-pvc.yaml

4. 部署NextCloud核心应用
kubectl apply -f 07-nc-deployment.yaml
kubectl apply -f 08-nc-svc.yaml
kubectl apply -f 06-edit-config.php-cm.yaml

5. 部署OnlyOffice
kubectl apply -f 09-onlyoffice.yaml

6. 部署Nginx代理
kubectl apply -f 10-nginx-configmap.yaml
kubectl apply -f 11-nginx.yaml

```

 验证部署状态

```
kubectl -n nextcloud get pods,svc,pvc
```

## 三、配置说明

### 关键配置项

1. **数据库认证**（03-db-deployment.yaml）

   ```
   - name: MYSQL_ROOT_PASSWORD
     value: xxxxxxxxx
   - name: MYSQL_PASSWORD
     value: xxxxxxxxx
   ```

2. **存储配置**（05-nextcloud-pvc.yaml）

   ```
   storageClassName: nfs-csi
   resources:
     requests:
       storage: 10Gi
   ```

3. **域名配置**（07-nc-deployment.yaml）

   ```
   - name: NEXTCLOUD_URL
     value: http://<someDomain>  # 需替换为实际域名
   ```

4. **OnlyOffice集成**（06-edit-config.php-cm.yaml）

   ```
   php occ config:system:set onlyoffice DocumentServerUrl --value="/ds-vpath/"
   php occ config:system:set onlyoffice DocumentServerInternalUrl --value="http://nextcloud-onlyoffice/"
   ```

### 访问方式

1. 通过Ingress访问：

   ```
   http://nextcloud.yq.com
   ```

   默认管理员账号：admin / 123456



## 四、06-edit-config.php-cm.yaml配置说明

`run.sh` 脚本的详细技术解释：

此脚本通过NextCloud的 `occ` 命令行工具完成以下关键配置操作：

```
# 步骤1. 下载并解压OnlyOffice插件
su -s /bin/sh www-data -c 'curl -O https://gitee.com/qingcaihub/nextcloud-onlyoffice/raw/master/onlyoffice.tar.gz && tar -xvf onlyoffice.tar.gz -C apps/ \

# 步骤2. 生成信任域名临时文件
; php occ --no-warnings config:system:get trusted_domains >> trusted_domain.tmp \

# 步骤3. 启用核心功能
; php occ --no-warnings app:enable onlyoffice \        # 激活OnlyOffice插件
; php occ --no-warnings app:enable files_external \   # 启用外部存储功能

# 步骤4. 配置OnlyOffice连接
; php occ --no-warnings config:system:set onlyoffice DocumentServerUrl --value="/ds-vpath/" \              # 设置文档服务外部访问路径
&& php occ --no-warnings config:system:set onlyoffice DocumentServerInternalUrl --value="http://nextcloud-onlyoffice/" \  # 内部服务地址
&& php occ --no-warnings config:system:set onlyoffice StorageUrl --value="http://nextcloud-nginx/" \      # 存储服务地址
&& php occ --no-warnings config:system:set overwrite.cli.url --value="http://nextcloud.yq.com/" \         # 覆盖CLI访问地址

# 步骤5. JWT安全配置
&& php occ --no-warnings config:system:set onlyoffice jwt_secret --value="secret" \                       # 设置JWT密钥（需与OnlyOffice服务端一致）

# 步骤6. 动态更新信任域名
&& ! grep -q "nextcloud.yq.com" trusted_domain.tmp \                # 检查域名是否已存在
&& TRUSTED_INDEX=$(cat trusted_domain.tmp | wc -l) \                # 计算当前域名数量
&& php occ --no-warnings config:system:set trusted_domains 0 --value="nextcloud.yq.com" \  # 强制设置主域名为索引0
&& php occ --no-warnings config:system:set trusted_domains 1 --value="nextcloud-nginx" \   # 设置内部服务名为索引1
; rm trusted_domain.tmp'                                            # 清理临时文件
```

------

### 关键技术细节

1. **用户上下文控制**

   ```
   su -s /bin/sh www-data -c '...'
   ```

   - 使用 `www-data` 用户身份执行命令，确保生成的文件权限与NextCloud运行用户一致

2. **信任域名动态更新**

   - 通过 `trusted_domain.tmp` 文件暂存现有配置
   - 使用 `grep` 检查域名是否已存在（`! grep -q` 表示"如果不存在"）
   - **强制覆盖策略**：直接设置索引0和1，而非动态追加，确保关键域名优先

3. **OnlyOffice服务对接**

   ```
   DocumentServerUrl="/ds-vpath/"                   # 通过Nginx反向代理的路径
   DocumentServerInternalUrl="http://nextcloud-onlyoffice/"  # Kubernetes内部服务地址
   ```

   - 双路径配置同时满足内外网访问需求
   - `StorageUrl` 指向Nginx服务实现文件缓存

4. **安全增强配置**

   ```
   jwt_secret="secret"  # 需与09-onlyoffice.yaml中的JWT_SECRET值完全一致
   ```

   - 使用JWT令牌验证确保OnlyOffice服务通信安全

------

### 配置验证方法

1. **检查已启用的应用**

   ```
   kubectl -n nextcloud exec nextcloud-app-0 -- php occ app:list
   ```

   预期输出应包含：

   ```
   - onlyoffice: 7.1.1
   - files_external: 2.3.0
   ```

2. **验证信任域名配置**

   ```
   kubectl -n nextcloud exec nextcloud-app-0 -- php occ config:system:get trusted_domains
   ```

   预期输出：

   ```
   0 => 'nextcloud.yq.com',
   1 => 'nextcloud-nginx'
   ```

3. **检查OnlyOffice服务状态**

   ```
   kubectl -n nextcloud exec nextcloud-app-0 -- curl -I http://nextcloud-onlyoffice/
   ```

   应返回 `HTTP/1.1 200 OK`

------

### 故障排查提示

1. **插件安装失败**

   - 检查网络连通性：`kubectl -n nextcloud exec nextcloud-app-0 -- curl -v http://yum.yq.com/yumrepos/www/nextcloud/onlyoffice.tar.gz`
   - 验证NFS存储权限：`kubectl -n nextcloud exec nextcloud-app-0 -- ls -l /var/www/html/apps/`

2. **JWT验证错误**

   - 对比检查两个位置的密钥是否一致：

     ```
     kubectl -n nextcloud exec nextcloud-app-0 -- php occ config:system:get onlyoffice jwt_secret
     kubectl -n nextcloud get statefulset nextcloud-onlyoffice -o yaml | grep JWT_SECRET
     ```

3. **域名不信任错误**

   - 临时添加调试命令：

     ```
     && php occ --no-warnings config:system:set loglevel --value=2 \  # 开启调试日志
     && tail -f /var/www/html/data/nextcloud.log
     ```
