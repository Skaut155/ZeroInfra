# Nodos
- cyborg: 172.16.4.37 - Nodo servidor
- asterix: 172.16.4.33 - Nodo agente

# Kubernetes
Actualmente se está utilizando la distribución de Kubernetes k3s. Se ha modificado su configuración para permitir la exposición de los puertos 8080-8089 a través de servicios.

Actualmente hay 4 pods de prueba de «Hello World» en ejecución para demostrar el funcionamiento multinodo y el acceso a Internet.

# Administración
SSH está habilitado en ambas máquinas.

Actualmente es posible conectarse mediante contraseña y clave pública.

En el futuro, se deshabilitará la autenticación mediante contraseña en ambas máquinas por seguridad. Los siguientes son los puertos de conexión de ssh:

- cyborg: 22037
- asterix: 22033

## Freelens
Un IDE de Kubernetes de código abierto que se utiliza para supervisar las distintas características del clúster.

Para poder utilizarlo hay que copiar el archivo .kube/config (no ubicado en este repositorio por temas de seguridad)

Tambien es necesario estar conectado a la VPN de FortiClient e iniciar un túnel SSH:

```bash
sh -N -L 6443:127.0.0.1:6443 alumne@nattech.fib.upc.edu -p 22037
```