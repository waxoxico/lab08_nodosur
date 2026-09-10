$TTL    604800
@       IN      SOA     ns1.lab08.nodosur.cl. admin.lab08.nodosur.cl. (
                              3         ; Serial (¡Aumentado a 3 para aplicar el cambio!)
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL

@       IN      NS      ns1.lab08.nodosur.cl.

ns1     IN      A       10.33.199.66    ; El DNS se mantiene en la red interna
db      IN      A       10.33.199.66    ; La Base de Datos se mantiene interna por seguridad (¡Excelente práctica!)
web1    IN      A       10.33.195.234   ; Servidor Web a la IP Pública
@       IN      A       10.33.195.234   ; El dominio raíz al WordPress (IP Pública)
www     IN      A       10.33.195.234   ; El subdominio www al WordPress (IP Pública)
