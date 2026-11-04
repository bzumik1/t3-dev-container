package smoke;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.sql.DriverManager;
import org.junit.jupiter.api.Test;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.postgresql.PostgreSQLContainer;

@Testcontainers
class PostgresContainerTest {

    @Container
    static final PostgreSQLContainer postgres = new PostgreSQLContainer("postgres:17-alpine");

    @Test
    void givenRunningPostgres_whenQueried_thenAnswers() throws Exception {
        try (var connection = DriverManager.getConnection(postgres.getJdbcUrl(), postgres.getUsername(), postgres.getPassword());
             var result = connection.createStatement().executeQuery("select 40 + 2")) {
            result.next();
            assertEquals(42, result.getInt(1));
        }
    }
}
