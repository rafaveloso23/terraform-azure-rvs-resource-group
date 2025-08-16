import os
from azure.identity import DefaultAzureCredential
from azure.graphrbac import GraphRbacManagementClient

# Substitua pelo ID do Enterprise App desejado
tenant_id = os.environ.get('0eed3ea8-f35c-4862-b14a-9809318064c7')
enterprise_app_id = os.environ.get('67371481-1e52-452b-8038-6da4cc05452e')

# Autenticação
credential = DefaultAzureCredential()
client = GraphRbacManagementClient(credential, tenant_id)

# Buscar informações do Enterprise App
app = client.applications.get(enterprise_app_id)

# Exibir atributos customizados (extension properties)
if hasattr(app, 'extension_properties'):
    print('Custom Attributes:') 
    for prop in app.extension_properties:
        print(f"Name: {prop.name}, Value: {prop.value}")
else:
    print('Nenhum custom attribute encontrado.')
